// Fase 6: tests unitarios de auth_service.dart contra un backend
// simulado con package:http/testing.dart (MockClient), sin backend real.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:speak_english/services/api_service.dart';
import 'package:speak_english/services/auth_service.dart';
import 'package:speak_english/services/token_storage.dart';

/// TokenStorage en memoria para tests: evita tocar
/// `flutter_secure_storage`, que depende de un canal de plataforma no
/// disponible al correr `flutter test`.
class FakeTokenStorage extends TokenStorage {
  String? _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> deleteToken() async => _token = null;
}

void main() {
  group('AuthService', () {
    late FakeTokenStorage tokenStorage;

    setUp(() {
      tokenStorage = FakeTokenStorage();
    });

    AuthService buildService(http.Client client) {
      // Se pasa el mismo tokenStorage a ApiService y a AuthService para
      // que el token que guarda login() sea el mismo que lee me() al
      // armar el header Authorization.
      final apiService = ApiService(client: client, tokenStorage: tokenStorage);
      return AuthService(apiService: apiService, tokenStorage: tokenStorage);
    }

    test('register exitoso (201) no lanza excepción', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/register');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], 'juan');
        expect(body['email'], 'juan@example.com');
        expect(body['password'], '12345678');
        return http.Response('', 201);
      });

      await buildService(client).register('juan', 'juan@example.com', '12345678');
    });

    test('register fallido lanza AuthException con el mensaje del backend', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'El email ya está registrado'}), 409);
      });

      expect(
        () => buildService(client).register('juan', 'juan@example.com', '12345678'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'El email ya está registrado',
          ),
        ),
      );
    });

    test('login exitoso guarda el token y lo retorna', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/login');
        return http.Response(jsonEncode({'access_token': 'token-123'}), 200);
      });

      final token = await buildService(client).login('juan@example.com', '12345678');

      expect(token, 'token-123');
      expect(await tokenStorage.readToken(), 'token-123');
    });

    test('login con credenciales inválidas lanza AuthException', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Credenciales inválidas'}), 401);
      });

      expect(
        () => buildService(client).login('juan@example.com', 'mala-clave'),
        throwsA(isA<AuthException>()),
      );
    });

    test('me() retorna el User cuando el backend responde 200', () async {
      await tokenStorage.saveToken('token-123');
      final client = MockClient((request) async {
        expect(request.url.path, '/auth/me');
        expect(request.headers['Authorization'], 'Bearer token-123');
        return http.Response(
          jsonEncode({
            'user': {'id': 1, 'username': 'juan', 'email': 'juan@example.com'},
          }),
          200,
        );
      });

      final user = await buildService(client).me();

      expect(user.id, 1);
      expect(user.username, 'juan');
      expect(user.email, 'juan@example.com');
    });

    test('me() lanza UnauthorizedException cuando el backend responde 401', () async {
      await tokenStorage.saveToken('token-vencido');
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Token expirado'}), 401);
      });

      expect(() => buildService(client).me(), throwsA(isA<UnauthorizedException>()));
    });
  });
}
