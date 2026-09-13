// Taller Semana 13, Bloque 4: valida el interceptor de renovación de
// `ApiService` contra un backend simulado con `package:http/testing.dart`
// (MockClient), sin backend real.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:speak_english/services/api_service.dart';
import 'package:speak_english/services/token_storage.dart';

/// TokenStorage en memoria para tests, con soporte de access + refresh
/// token (evita tocar `flutter_secure_storage`, que depende de un canal
/// de plataforma no disponible al correr `flutter test`).
class FakeTokenStorage extends TokenStorage {
  FakeTokenStorage({String? accessToken, String? refreshToken})
      : _token = accessToken,
        _refreshToken = refreshToken;

  String? _token;
  String? _refreshToken;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveRefreshToken(String token) async => _refreshToken = token;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> deleteToken() async {
    _token = null;
    _refreshToken = null;
  }
}

void main() {
  group('ApiService — interceptor de renovación (Bloque 4)', () {
    test(
        'ante un 401 renueva el token con el refresh_token y reintenta '
        'la petición original una sola vez', () async {
      var refreshCalls = 0;
      var roomsCalls = 0;
      final tokenStorage = FakeTokenStorage(
        accessToken: 'access-vencido',
        refreshToken: 'refresh-valido',
      );

      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          expect(request.headers['Authorization'], 'Bearer refresh-valido');
          return http.Response(jsonEncode({'access_token': 'access-nuevo'}), 200);
        }

        roomsCalls++;
        if (request.headers['Authorization'] == 'Bearer access-vencido') {
          // Primer intento: todavía con el token vencido -> 401.
          return http.Response(jsonEncode({'error': 'Token expirado'}), 401);
        }
        // Reintento tras la renovación: ya debería llegar con el token nuevo.
        expect(request.headers['Authorization'], 'Bearer access-nuevo');
        return http.Response(jsonEncode({'rooms': []}), 200);
      });

      final apiService = ApiService(client: client, tokenStorage: tokenStorage);
      final response = await apiService.authorizedGet('/rooms/list');

      expect(response.statusCode, 200);
      expect(await tokenStorage.readToken(), 'access-nuevo');
      expect(refreshCalls, 1);
      expect(roomsCalls, 2); // 401 original + reintento exitoso
    });

    test(
        'si el refresh_token también es inválido, no reintenta en bucle '
        'y lanza UnauthorizedException', () async {
      var refreshCalls = 0;
      final tokenStorage = FakeTokenStorage(
        accessToken: 'access-vencido',
        refreshToken: 'refresh-vencido',
      );

      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          return http.Response(jsonEncode({'error': 'Refresh inválido'}), 401);
        }
        return http.Response(jsonEncode({'error': 'Token expirado'}), 401);
      });

      final apiService = ApiService(client: client, tokenStorage: tokenStorage);

      await expectLater(
        apiService.authorizedGet('/rooms/list'),
        throwsA(isA<UnauthorizedException>()),
      );
      // Protección contra bucle: el refresh se intenta una sola vez,
      // nunca en cada reintento.
      expect(refreshCalls, 1);
    });

    test('sin refresh_token guardado, no llama a /auth/refresh y lanza UnauthorizedException',
        () async {
      final tokenStorage = FakeTokenStorage(accessToken: 'access-vencido');
      var refreshCalls = 0;

      final client = MockClient((request) async {
        if (request.url.path == '/auth/refresh') refreshCalls++;
        return http.Response(jsonEncode({'error': 'Token expirado'}), 401);
      });

      final apiService = ApiService(client: client, tokenStorage: tokenStorage);

      await expectLater(
        apiService.authorizedGet('/rooms/list'),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(refreshCalls, 0);
    });
  });
}
