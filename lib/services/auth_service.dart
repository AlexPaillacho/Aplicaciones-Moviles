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

/// Servicio de autenticación contra el backend Flask.
class AuthService {
  AuthService({ApiService? apiService, TokenStorage? tokenStorage})
      : _apiService = apiService ?? ApiService(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final ApiService _apiService;
  final TokenStorage _tokenStorage;

  /// `POST /auth/register`. Lanza `AuthException` con el mensaje del
  /// backend si falla (ej. email ya registrado -> 409).
  Future<void> register(String username, String email, String password) async {
    final response = await _apiService.post('/auth/register', body: {
      'username': username,
      'email': email,
      'password': password,
    });

    if (response.statusCode != 201) {
      throw AuthException(_extractError(response.body));
    }
  }

  /// `POST /auth/login`. Guarda el `access_token` en `TokenStorage` y lo
  /// retorna. Lanza `AuthException` con el mensaje del backend si falla
  /// (credenciales inválidas -> 401).
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
    await _tokenStorage.saveToken(token);
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

  Future<void> logout() {
    return _tokenStorage.deleteToken();
  }

  String _extractError(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      return data['error'] as String? ?? 'Error desconocido';
    } catch (_) {
      return 'Error desconocido';
    }
  }
}
