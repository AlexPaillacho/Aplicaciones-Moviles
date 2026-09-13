import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../core/constants.dart';
import 'connectivity_service.dart';
import 'token_storage.dart';

/// Excepción lanzada cuando el backend responde 401.
///
/// Se maneja de forma centralizada en `ApiService` (Fase 5): cuando
/// cualquier llamada autenticada recibe un 401, se dispara
/// [ApiService.onUnauthorized] (logout + navegar a `/login`, configurado
/// una sola vez en `app.dart`) y además se lanza esta excepción por si el
/// llamador quiere hacer algo adicional (o simplemente ignorarla, ya que
/// la navegación global ya ocurrió).
class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message = 'No autorizado']);
  final String message;

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Base común de las 3 familias de "fallo de conexión" que distingue el
/// taller (Bloque 7): sin conexión, timeout y servidor caído. Se lanza
/// desde un único punto (`ApiService._guarded`) para que todos los
/// servicios (`auth_service.dart`, `rooms_remote_source.dart`) y las
/// pantallas que los consumen no dupliquen `try/catch` de
/// `SocketException`/`TimeoutException` en cada método.
///
/// Un `catch` contra este tipo base (ej. `RoomsRepository.trySyncPending`,
/// que necesita tratar igual cualquier fallo de red para cortar la cola
/// y esperar la reconexión) sigue capturando las tres variantes de abajo
/// sin cambios, gracias al polimorfismo de `on`. Las variantes existen
/// para que la UI, si quiere, muestre un mensaje más preciso que el
/// genérico "no se pudo conectar".
abstract class NetworkException implements Exception {
  const NetworkException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Familia 1: el dispositivo no tiene ninguna interfaz de red activa en
/// este momento (`ConnectivityService.isOnline()` respondió `false`
/// justo cuando falló la petición).
class NoConnectionException extends NetworkException {
  const NoConnectionException()
      : super('Sin conexión a internet. Revisa tu wifi o datos móviles.');
}

/// Familia 2: la petición superó `ApiClient.requestTimeout` sin
/// recibir respuesta (`TimeoutException` de `Future.timeout`).
class RequestTimeoutException extends NetworkException {
  const RequestTimeoutException()
      : super('El servidor tardó demasiado en responder. Intenta de nuevo.');
}

/// Familia 3: el dispositivo sí tiene una interfaz de red activa, pero
/// no se pudo alcanzar el backend (`SocketException`/`HttpException`:
/// servidor caído, puerto cerrado, DNS que no resuelve, etc.). Se
/// distingue de [NoConnectionException] consultando
/// `ConnectivityService` en el momento del fallo — mismo error de Dart
/// (`SocketException`), causas distintas para el usuario.
class ServerUnavailableException extends NetworkException {
  const ServerUnavailableException()
      : super('No se pudo conectar con el servidor. Intenta más tarde.');
}

/// Familia 4: el backend respondió 422 (los datos enviados no pasaron su
/// validación — email/nombre faltante, etc.). Se intercepta en el mismo
/// punto único que las tres de arriba (`ApiService._guarded`) para que
/// ningún servicio tenga que repetir el `if (statusCode == 422)`: antes
/// de este bloque cada uno solo distinguía éxito/fracaso genérico
/// (`RoomException`/`AuthException`) y esta familia se perdía en el
/// mensaje del backend sin ningún tratamiento especial.
class ValidationException implements Exception {
  const ValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Único punto de configuración de la URL base del backend.
///
/// Ninguna pantalla debe hacer `http.get`/`http.post` directo: todo pasa
/// por aquí (o por los servicios que lo envuelven, como `auth_service.dart`
/// y `rooms_remote_source.dart`).
class ApiService {
  ApiService({
    String? baseUrl,
    http.Client? client,
    TokenStorage? tokenStorage,
    ConnectivityService? connectivity,
  })  : baseUrl = baseUrl ?? AppConstants.apiBaseUrl,
        _client = client ?? ApiClient().httpClient,
        _tokenStorage = tokenStorage ?? TokenStorage(),
        _connectivity = connectivity ?? ConnectivityService();

  /// Instancia única para uso en producción (Bloque 2): todos los
  /// servicios (`AuthService`, `RoomsRemoteSource`, etc.) deben compartir
  /// esta instancia en vez de crear `ApiService()` cada uno por su
  /// cuenta. Los tests siguen creando instancias propias con
  /// `ApiService(client: ..., tokenStorage: ...)` para inyectar dobles,
  /// sin tocar esta instancia compartida.
  static final ApiService instance = ApiService();

  final String baseUrl;
  final http.Client _client;
  final TokenStorage _tokenStorage;

  /// Usado únicamente para distinguir [NoConnectionException] de
  /// [ServerUnavailableException] cuando falla una petición (Bloque 7):
  /// ambas nacen del mismo `SocketException` de Dart.
  final ConnectivityService _connectivity;

  /// Callback global para manejar un 401 en cualquier llamada
  /// autenticada. Se configura una sola vez en `app.dart` (Fase 5) y
  /// normalmente hace `authProvider.logout()` + navega a `/login`.
  static void Function()? onUnauthorized;

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  /// Ejecuta [action] con el timeout explícito de `ApiClient` (Bloque
  /// 2), pasa por el interceptor de logging (Bloque 8, ver
  /// `_logRequest`/`_logResponse`/`_logFailure`) y traduce cada fallo a
  /// UNA de las 4 familias de dominio del taller (Bloque 7), en vez de
  /// un `NetworkException` genérico único: [RequestTimeoutException],
  /// [NoConnectionException] o [ServerUnavailableException] para los 3
  /// fallos de conexión, y [ValidationException] si el backend sí
  /// respondió pero con un 422. Único punto donde se traducen estos
  /// errores, para no repetirlo en cada servicio (`auth_service.dart`,
  /// `rooms_remote_source.dart`).
  ///
  /// [method] y [uri] son solo para el log — no afectan la petición en
  /// sí (ya va armada dentro de [action]). [headers] se loguea tal cual
  /// llega, salvo `Authorization`, que siempre se oculta (Bloque 8).
  ///
  /// Antes de este bloque no había ningún timeout configurado: una
  /// petición colgada (servidor caído a medio TCP handshake, etc.)
  /// nunca terminaba, así que `TimeoutException` nunca se disparaba en
  /// la práctica pese a que ya se capturaba. Y las 3 causas de conexión
  /// caían todas en el mismo mensaje genérico, sin forma de saber cuál
  /// había ocurrido.
  Future<http.Response> _guarded(
    Future<http.Response> Function() action, {
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
  }) async {
    _logRequest(method, uri, headers);
    final stopwatch = Stopwatch()..start();

    late final http.Response response;
    try {
      response = await action().timeout(ApiClient.requestTimeout);
    } on TimeoutException {
      _logFailure(method, uri, stopwatch, 'timeout');
      throw const RequestTimeoutException();
    } on SocketException {
      // Mismo error de Dart para dos causas distintas: sin ninguna
      // interfaz de red activa (familia 1) vs. red activa pero backend
      // inalcanzable (familia 3). Solo `ConnectivityService` puede
      // distinguirlas.
      final online = await _connectivity.isOnline();
      final exception =
          online ? const ServerUnavailableException() : const NoConnectionException();
      _logFailure(method, uri, stopwatch, exception.message);
      throw exception;
    } on HttpException {
      _logFailure(method, uri, stopwatch, 'servidor caído (HttpException)');
      throw const ServerUnavailableException();
    }

    _logResponse(method, uri, stopwatch, response.statusCode);

    if (response.statusCode == 422) {
      throw ValidationException(_extractValidationMessage(response.body));
    }

    return response;
  }

  /// Interceptor de logging (Bloque 8, verificación de seguridad).
  ///
  /// Dos reglas de seguridad, ambas obligatorias por el taller:
  ///
  /// 1. Nunca se loguea el header `Authorization` en texto plano — ni el
  ///    access token ni el refresh token deben terminar en la consola ni
  ///    en un log persistido. Se reemplaza por `[oculto]` (`_redacted`).
  /// 2. El interceptor se apaga POR COMPLETO en producción
  ///    (`ApiClient.isProduction`, Bloque 2): en un build de release no
  ///    se emite ni una línea, ni siquiera con el header ya oculto —
  ///    evita que cualquier log del dispositivo/consola en producción
  ///    filtre rutas, tiempos de respuesta o metadata de la API.
  ///
  /// Deliberadamente NUNCA se loguea el cuerpo (`body`) de la petición:
  /// `POST /auth/login` y `POST /auth/register` llevan la contraseña en
  /// texto plano en el body, así que loguearlo — aunque sea solo en
  /// desarrollo — ya sería una fuga. Por eso estos tres métodos solo
  /// reciben `method`, `uri` y `headers`, nunca el body.
  void _logRequest(String method, Uri uri, Map<String, String> headers) {
    if (ApiClient.isProduction) return;
    debugPrint('[HTTP] --> $method ${uri.path} headers=${_redacted(headers)}');
  }

  void _logResponse(String method, Uri uri, Stopwatch stopwatch, int statusCode) {
    if (ApiClient.isProduction) return;
    debugPrint('[HTTP] <-- $statusCode $method ${uri.path} (${stopwatch.elapsedMilliseconds}ms)');
  }

  void _logFailure(String method, Uri uri, Stopwatch stopwatch, String reason) {
    if (ApiClient.isProduction) return;
    debugPrint(
      '[HTTP] <-- ERROR $method ${uri.path} (${stopwatch.elapsedMilliseconds}ms): $reason',
    );
  }

  /// Copia [headers] reemplazando el valor de `Authorization` por
  /// `[oculto]`, si está presente. Nunca modifica los headers reales
  /// que se mandan al backend — solo la copia que se imprime en el log.
  Map<String, String> _redacted(Map<String, String> headers) {
    if (!headers.containsKey('Authorization')) return headers;
    return {...headers, 'Authorization': '[oculto]'};
  }

  String _extractValidationMessage(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      return data['error'] as String? ?? 'Los datos enviados no son válidos';
    } catch (_) {
      return 'Los datos enviados no son válidos';
    }
  }

  /// Interceptor de autenticación (Bloque 3): único punto que arma el
  /// header `Authorization` antes de cada petición autenticada, leyendo
  /// el token desde `TokenStorage` (almacenamiento cifrado, Semana 12).
  /// Todos los métodos `authorized*` pasan por acá — ninguno lee el
  /// token ni arma el header por su cuenta.
  Future<Map<String, String>> _authHeader() async {
    final token = await _tokenStorage.readToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Refresh en curso, si lo hay. Si varias peticiones reciben 401 al
  /// mismo tiempo, todas esperan este mismo `Future` en vez de disparar
  /// cada una su propio `POST /auth/refresh` (evita renovaciones
  /// duplicadas en paralelo).
  Future<bool>? _refreshInFlight;

  /// Interceptor de renovación (Bloque 4): ante un 401, intenta renovar
  /// el `access_token` con el `refresh_token` guardado. Devuelve `true`
  /// si la renovación tuvo éxito (nuevo `access_token` ya guardado en
  /// `TokenStorage`), `false` si no había `refresh_token` o el backend
  /// lo rechazó (vencido/inválido) o hubo un fallo de red al intentarlo.
  Future<bool> _tryRefreshToken() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final uri = _buildUri('/auth/refresh');
      final headers = {..._jsonHeaders, 'Authorization': 'Bearer $refreshToken'};
      final response = await _guarded(
        () => _client.post(uri, headers: headers),
        method: 'POST',
        uri: uri,
        headers: headers, // el refresh_token se oculta igual que el access token
      );

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final newAccessToken = data['access_token'] as String?;
      if (newAccessToken == null) return false;

      await _tokenStorage.saveToken(newAccessToken);
      return true;
    } on NetworkException {
      // Sin conexión al intentar renovar: se trata igual que un
      // refresh fallido, así que la petición original cae al 401
      // normal (`_checkAuthorized`) en vez de reintentar indefinidamente.
      return false;
    }
  }

  /// Envuelve cualquier petición autenticada con el interceptor de
  /// renovación (Bloque 4): arma el header de auth (Bloque 3), envía la
  /// petición, y si responde 401 intenta renovar el token una única vez
  /// y reintenta [send] con el token nuevo.
  ///
  /// [method] y [uri] son solo para el interceptor de logging del
  /// `_guarded` interno (Bloque 8) — no cambian la petición real.
  ///
  /// Protección contra bucles: [retry] se apaga en el reintento, así
  /// que un segundo 401 (refresh también inválido/vencido, o el backend
  /// simplemente sigue rechazando el token nuevo) cae directo a
  /// `_checkAuthorized` sin volver a intentar renovar.
  Future<http.Response> _authorizedRequest(
    String method,
    Uri uri,
    Future<http.Response> Function(Map<String, String> authHeader) send, {
    bool retry = true,
  }) async {
    final authHeader = await _authHeader();
    final response = await _guarded(
      () => send(authHeader),
      method: method,
      uri: uri,
      headers: authHeader,
    );

    if (response.statusCode == 401 && retry) {
      final renewed = await _tryRefreshToken();
      if (renewed) {
        return _authorizedRequest(method, uri, send, retry: false);
      }
    }

    return _checkAuthorized(response);
  }

  /// Revisa la respuesta de una llamada autenticada: si es 401, dispara
  /// [onUnauthorized] y lanza `UnauthorizedException`.
  http.Response _checkAuthorized(http.Response response) {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
      throw const UnauthorizedException();
    }
    return response;
  }

  /// GET público (sin token), ej. `GET /rooms/list`.
  Future<http.Response> get(String path, {Map<String, String>? queryParameters}) {
    final uri = _buildUri(path, queryParameters);
    return _guarded(() => _client.get(uri), method: 'GET', uri: uri);
  }

  /// POST público (sin token), ej. `POST /auth/login`.
  ///
  /// [body] nunca se pasa a `_guarded`/al log (Bloque 8): tanto login
  /// como register llevan la contraseña en texto plano acá.
  Future<http.Response> post(String path, {Map<String, dynamic>? body}) {
    final uri = _buildUri(path);
    return _guarded(
      () => _client.post(uri, headers: _jsonHeaders, body: body != null ? jsonEncode(body) : null),
      method: 'POST',
      uri: uri,
      headers: _jsonHeaders,
    );
  }

  /// GET autenticado. Pasa por el interceptor de autenticación
  /// (`_authHeader`, Bloque 3) y el de renovación (`_authorizedRequest`,
  /// Bloque 4).
  Future<http.Response> authorizedGet(String path, {Map<String, String>? queryParameters}) {
    final uri = _buildUri(path, queryParameters);
    return _authorizedRequest(
      'GET',
      uri,
      (authHeader) => _client.get(uri, headers: authHeader),
    );
  }

  /// POST autenticado. Igual manejo de token y renovación que `authorizedGet`.
  Future<http.Response> authorizedPost(String path, {Map<String, dynamic>? body}) {
    final uri = _buildUri(path);
    return _authorizedRequest(
      'POST',
      uri,
      (authHeader) => _client.post(
        uri,
        headers: {..._jsonHeaders, ...authHeader},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  /// PUT autenticado (se necesita en la Fase 3 para `PUT /rooms/<id>`).
  Future<http.Response> authorizedPut(String path, {Map<String, dynamic>? body}) {
    final uri = _buildUri(path);
    return _authorizedRequest(
      'PUT',
      uri,
      (authHeader) => _client.put(
        uri,
        headers: {..._jsonHeaders, ...authHeader},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  /// DELETE autenticado (se necesita en la Fase 3 para `DELETE /rooms/<id>`).
  Future<http.Response> authorizedDelete(String path) {
    final uri = _buildUri(path);
    return _authorizedRequest(
      'DELETE',
      uri,
      (authHeader) => _client.delete(uri, headers: authHeader),
    );
  }

  /// POST multipart autenticado (se necesita en la Fase 4 para enviar el
  /// audio grabado a `POST /rooms/<id>/process-audio`, campo `audio`).
  Future<http.Response> authorizedMultipartPost(
    String path, {
    required String fileField,
    required File file,
  }) {
    final uri = _buildUri(path);
    return _authorizedRequest(
      'POST',
      uri,
      (authHeader) async {
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll(authHeader)
          ..files.add(await http.MultipartFile.fromPath(fileField, file.path));

        final streamedResponse = await _client.send(request);
        return http.Response.fromStream(streamedResponse);
      },
    );
  }
}
