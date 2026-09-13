import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper sobre almacenamiento seguro del token JWT.
///
/// Usa `flutter_secure_storage` (Keychain en iOS, Keystore en Android)
/// en vez de `SharedPreferences`, porque el token no debe guardarse en
/// texto plano.
///
/// Taller Semana 13 (Bloque 4): además del `access_token` (de vida
/// corta) se guarda el `refresh_token` (de vida larga) por separado,
/// en el mismo almacenamiento cifrado, para que el interceptor de
/// renovación de `ApiService` pueda usarlo cuando una petición
/// autenticada recibe 401.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  /// Guarda el `refresh_token` devuelto por `POST /auth/login`.
  Future<void> saveRefreshToken(String token) {
    return _storage.write(key: _refreshTokenKey, value: token);
  }

  /// Lee el `refresh_token` guardado. `null` si nunca se guardó uno
  /// (ej. login contra un backend viejo que no lo devuelve).
  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  /// Guarda ambos tokens en una sola llamada (usado por `AuthService.login`).
  /// [refreshToken] es opcional para no romper compatibilidad si algún
  /// día el backend deja de mandarlo.
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {
    await saveToken(accessToken);
    if (refreshToken != null) {
      await saveRefreshToken(refreshToken);
    }
  }

  /// Borra ambos tokens (access y refresh). Se usa en logout: dejar el
  /// refresh_token vivo tras un logout permitiría "resucitar" la sesión
  /// sin login.
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
