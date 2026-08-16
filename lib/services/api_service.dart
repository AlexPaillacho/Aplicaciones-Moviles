import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
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

/// Excepción para fallos de conexión (sin internet, servidor caído,
/// timeout). Se lanza desde un único punto (`ApiService`) para que todos
/// los servicios (`auth_service.dart`, `rooms_service.dart`) y las
/// pantallas que los consumen puedan mostrar el mismo mensaje sin
/// duplicar `try/catch` de `SocketException`/`TimeoutException` en cada
/// método.
class NetworkException implements Exception {
  const NetworkException([this.message = 'No se pudo conectar al servidor']);
  final String message;

  @override
  String toString() => message;
}

/// Único punto de configuración de la URL base del backend.
///
/// Ninguna pantalla debe hacer `http.get`/`http.post` directo: todo pasa
/// por aquí (o por los servicios que lo envuelven, como `auth_service.dart`
/// y `rooms_service.dart`).
class ApiService {
  ApiService({
    this.baseUrl = AppConstants.apiBaseUrl,
    http.Client? client,
    TokenStorage? tokenStorage,
  })  : _client = client ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final String baseUrl;
  final http.Client _client;
  final TokenStorage _tokenStorage;

  /// Callback global para manejar un 401 en cualquier llamada
  /// autenticada. Se configura una sola vez en `app.dart` (Fase 5) y
  /// normalmente hace `authProvider.logout()` + navega a `/login`.
  static void Function()? onUnauthorized;

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  /// Ejecuta [action] y traduce fallos de conexión (`SocketException`,
  /// `TimeoutException`) en `NetworkException`. Único punto donde se
  /// capturan estos errores, para no repetirlo en cada servicio.
  Future<http.Response> _guarded(Future<http.Response> Function() action) async {
    try {
      return await action();
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException();
    } on HttpException {
      throw const NetworkException();
    }
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
    return _guarded(() => _client.get(_buildUri(path, queryParameters)));
  }

  /// POST público (sin token), ej. `POST /auth/login`.
  Future<http.Response> post(String path, {Map<String, dynamic>? body}) {
    return _guarded(() => _client.post(
          _buildUri(path),
          headers: _jsonHeaders,
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  /// GET autenticado. Agrega `Authorization: Bearer <token>` leyendo el
  /// token desde `TokenStorage`. Si el backend responde 401, dispara el
  /// manejo centralizado y lanza `UnauthorizedException`.
  Future<http.Response> authorizedGet(String path, {Map<String, String>? queryParameters}) async {
    final token = await _tokenStorage.readToken();
    final response = await _guarded(() => _client.get(
          _buildUri(path, queryParameters),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ));
    return _checkAuthorized(response);
  }

  /// POST autenticado. Igual manejo de token y de 401 que `authorizedGet`.
  Future<http.Response> authorizedPost(String path, {Map<String, dynamic>? body}) async {
    final token = await _tokenStorage.readToken();
    final response = await _guarded(() => _client.post(
          _buildUri(path),
          headers: {
            ..._jsonHeaders,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body != null ? jsonEncode(body) : null,
        ));
    return _checkAuthorized(response);
  }

  /// PUT autenticado (se necesita en la Fase 3 para `PUT /rooms/<id>`).
  Future<http.Response> authorizedPut(String path, {Map<String, dynamic>? body}) async {
    final token = await _tokenStorage.readToken();
    final response = await _guarded(() => _client.put(
          _buildUri(path),
          headers: {
            ..._jsonHeaders,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body != null ? jsonEncode(body) : null,
        ));
    return _checkAuthorized(response);
  }

  /// DELETE autenticado (se necesita en la Fase 3 para `DELETE /rooms/<id>`).
  Future<http.Response> authorizedDelete(String path) async {
    final token = await _tokenStorage.readToken();
    final response = await _guarded(() => _client.delete(
          _buildUri(path),
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ));
    return _checkAuthorized(response);
  }

  /// POST multipart autenticado (se necesita en la Fase 4 para enviar el
  /// audio grabado a `POST /rooms/<id>/process-audio`, campo `audio`).
  Future<http.Response> authorizedMultipartPost(
    String path, {
    required String fileField,
    required File file,
  }) async {
    final token = await _tokenStorage.readToken();
    final response = await _guarded(() async {
      final request = http.MultipartRequest('POST', _buildUri(path))
        ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'})
        ..files.add(await http.MultipartFile.fromPath(fileField, file.path));

      final streamedResponse = await _client.send(request);
      return http.Response.fromStream(streamedResponse);
    });
    return _checkAuthorized(response);
  }
}
