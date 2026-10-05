import 'dart:convert';

import '../models/user.dart';
import 'api_service.dart';
import 'token_storage.dart';

/// Excepción con el mensaje de error tal cual lo devuelve el backend
/// (clave `error` del JSON), para mostrarlo directo en la UI.
class AuthException implements Exception {
  const AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Mensaje único para un correo que no cumple la regla de Gmail
/// (el backend responde exactamente lo mismo con 422).
const String gmailErrorMessage =
    'Datos incorrectos: el correo debe terminar en @gmail.com';

final RegExp _gmailRegExp = RegExp(r'^[a-z0-9._%+\-]+@gmail\.com$');

/// `true` si [email] es una dirección `algo@gmail.com`.
bool isValidGmail(String email) =>
    _gmailRegExp.hasMatch(email.trim().toLowerCase());

/// Servicio de autenticación contra el backend Flask.
class AuthService {
  AuthService({ApiService? apiService, TokenStorage? tokenStorage})
      : _apiService = apiService ?? ApiService.instance,
        _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiService _apiService;
  final TokenStorage _tokenStorage;

  /// `POST /auth/register`. Lanza `AuthException` con el mensaje del
  /// backend si falla (ej. email ya registrado -> 409).
  Future<void> register(String username, String email, String password) async {
    // Misma regla que el backend: así el mensaje sale al instante y
    // sin depender del servidor.
    if (!isValidGmail(email)) throw const AuthException(gmailErrorMessage);

    final response = await _apiService.post('/auth/register', body: {
      'username': username,
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    if (response.statusCode != 201) {
      throw AuthException(_extractError(response.body));
    }
  }

  /// `POST /auth/login`. Guarda `access_token` y `refresh_token` (Bloque
  /// 4) en `TokenStorage` y retorna el `access_token`. Lanza
  /// `AuthException` con el mensaje del backend si falla (credenciales
  /// inválidas -> 401).
  Future<String> login(String email, String password) async {
    final response = await _apiService.post('/auth/login', body: {
      'email': email,
      'password': password,
    });

    if (response.statusCode != 200) {
      throw AuthException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'] as String;
    final refreshToken = data['refresh_token'] as String?;
    await _tokenStorage.saveTokens(accessToken: token, refreshToken: refreshToken);
    return token;
  }

  /// `GET /auth/me`. El backend responde `{"user": {...}}`; extraemos la
  /// clave `user`. Puede lanzar `UnauthorizedException` (token vencido o
  /// inválido), que se maneja en la Fase 5.
  Future<User> me() async {
    final response = await _apiService.authorizedGet('/auth/me');

    if (response.statusCode != 200) {
      throw AuthException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Callback global opcional, configurado una sola vez en `app.dart`,
  /// para limpiar cualquier almacén local que no sea el token (ej. la
  /// caché de rooms y la cola offline en `RoomsLocalSource`, vía `RoomsRepository`). El taller
  /// de Semana 12 exige borrar la totalidad del almacén local al cerrar
  /// sesión, no solo el token.
  static Future<void> Function()? onLogout;

  Future<void> logout() async {
    await _tokenStorage.deleteToken();
    await onLogout?.call();
  }

  String _extractError(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data is Map<String, dynamic>) {
        for (final key in const ['error', 'message', 'msg', 'detail']) {
          final value = data[key];
          if (value is String && value.trim().isNotEmpty) return value;
        }
      }
    } catch (_) {
      // cuerpo vacío o no-JSON: cae al mensaje genérico
    }
    return 'Datos incorrectos. Revisa la información e intenta de nuevo.';
  }
}
