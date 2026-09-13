// Taller Semana 13, Bloque 7: valida que `ApiService._guarded` traduzca
// cada fallo a la familia de dominio correcta (sin conexión / servidor
// caído / 422 validación), contra un backend simulado con
// `package:http/testing.dart` (MockClient), sin backend real.
//
// El timeout (la 4ta familia, `RequestTimeoutException`) no se cubre acá:
// `ApiClient.requestTimeout` es una constante de 15s y no hay forma de
// inyectar un timeout más corto sin tocar producción solo para testear,
// así que ese caso se valida manualmente contra el backend real (ver
// guion del video, Bloque 10).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:speak_english/services/api_service.dart';
import 'package:speak_english/services/connectivity_service.dart';
import 'package:speak_english/services/token_storage.dart';

/// TokenStorage en memoria para tests (evita `flutter_secure_storage`,
/// que depende de un canal de plataforma no disponible en `flutter test`).
class FakeTokenStorage extends TokenStorage {
  @override
  Future<void> saveToken(String token) async {}
  @override
  Future<String?> readToken() async => null;
  @override
  Future<void> saveRefreshToken(String token) async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> deleteToken() async {}
}

/// Doble de `ConnectivityService` que responde lo que el test necesite,
/// sin tocar `connectivity_plus` (canal de plataforma no disponible acá).
class FakeConnectivityService extends ConnectivityService {
  FakeConnectivityService(this._online);
  final bool _online;

  @override
  Future<bool> isOnline() async => _online;
}

void main() {
  group('ApiService — familias de error (Bloque 7)', () {
    test('un 422 lanza ValidationException con el mensaje del backend', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'name es requerido'}),
          422,
        );
      });
      final apiService = ApiService(
        client: client,
        tokenStorage: FakeTokenStorage(),
        connectivity: FakeConnectivityService(true),
      );

      await expectLater(
        apiService.post('/rooms', body: {}),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'name es requerido',
          ),
        ),
      );
    });

    test(
        'SocketException con el dispositivo ONLINE lanza '
        'ServerUnavailableException (familia 3: servidor caído)', () async {
      final client = MockClient((request) async {
        throw const SocketException('Connection refused');
      });
      final apiService = ApiService(
        client: client,
        tokenStorage: FakeTokenStorage(),
        connectivity: FakeConnectivityService(true),
      );

      await expectLater(
        apiService.get('/rooms/list'),
        throwsA(isA<ServerUnavailableException>()),
      );
    });

    test(
        'SocketException con el dispositivo OFFLINE lanza '
        'NoConnectionException (familia 1: sin conexión)', () async {
      final client = MockClient((request) async {
        throw const SocketException('Network is unreachable');
      });
      final apiService = ApiService(
        client: client,
        tokenStorage: FakeTokenStorage(),
        connectivity: FakeConnectivityService(false),
      );

      await expectLater(
        apiService.get('/rooms/list'),
        throwsA(isA<NoConnectionException>()),
      );
    });

    test('una respuesta 200 normal no se ve afectada por los nuevos casos', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'rooms': []}), 200);
      });
      final apiService = ApiService(
        client: client,
        tokenStorage: FakeTokenStorage(),
        connectivity: FakeConnectivityService(true),
      );

      final response = await apiService.get('/rooms/list');
      expect(response.statusCode, 200);
    });

    test(
        'NoConnectionException y ServerUnavailableException siguen siendo '
        'capturables como NetworkException (compatibilidad con '
        'RoomsRepository)', () async {
      expect(const NoConnectionException(), isA<NetworkException>());
      expect(const ServerUnavailableException(), isA<NetworkException>());
      expect(const RequestTimeoutException(), isA<NetworkException>());
    });
  });
}
