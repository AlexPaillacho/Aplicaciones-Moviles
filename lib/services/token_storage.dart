import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper sobre almacenamiento seguro del token JWT.
///
/// Usa `flutter_secure_storage` (Keychain en iOS, Keystore en Android)
/// en vez de `SharedPreferences`, porque el token no debe guardarse en
/// texto plano.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'access_token';

  Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() {
    return _storage.delete(key: _tokenKey);
  }
}
