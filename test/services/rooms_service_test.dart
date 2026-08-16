// Fase 6: tests unitarios de rooms_service.dart contra un backend
// simulado con package:http/testing.dart (MockClient), sin backend real.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:speak_english/services/api_service.dart';
import 'package:speak_english/services/rooms_service.dart';
import 'package:speak_english/services/token_storage.dart';

/// TokenStorage en memoria para tests: evita tocar
/// `flutter_secure_storage`, que depende de un canal de plataforma no
/// disponible al correr `flutter test`.
class FakeTokenStorage extends TokenStorage {
  FakeTokenStorage([this._token]);

  String? _token;

  @override
  Future<void> saveToken(String token) async => _token = token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> deleteToken() async => _token = null;
}

Map<String, dynamic> _roomJson({
  int id = 1,
  String name = 'Sala de prueba',
  bool active = true,
  int hostId = 7,
  String hostUsername = 'juan',
}) {
  return {
    'id': id,
    'name': name,
    'active': active,
    'host': {'id': hostId, 'username': hostUsername},
  };
}

void main() {
  group('RoomsService', () {
    RoomsService buildService(http.Client client, {String? token}) {
      final apiService = ApiService(client: client, tokenStorage: FakeTokenStorage(token));
      return RoomsService(apiService);
    }

    test('listRooms retorna la lista de salas (GET /rooms/list, sin JWT)', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/rooms/list');
        expect(request.url.queryParameters['optimized'], 'true');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'rooms': [_roomJson(id: 1, name: 'Sala 1'), _roomJson(id: 2, name: 'Sala 2')],
          }),
          200,
        );
      });

      final rooms = await buildService(client).listRooms();

      expect(rooms, hasLength(2));
      expect(rooms.first.name, 'Sala 1');
      expect(rooms.first.hostUsername, 'juan');
    });

    test('listRooms lanza RoomException si el backend responde error', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Error de servidor'}), 500);
      });

      expect(() => buildService(client).listRooms(), throwsA(isA<RoomException>()));
    });

    test('getRoom retorna la sala (GET /rooms/<id>, sin JWT)', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/rooms/5');
        return http.Response(jsonEncode({'room': _roomJson(id: 5, name: 'Sala 5')}), 200);
      });

      final room = await buildService(client).getRoom(5);

      expect(room.id, 5);
      expect(room.name, 'Sala 5');
    });

    test('createRoom envía el token y el nombre (POST /rooms)', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rooms');
        expect(request.headers['Authorization'], 'Bearer token-abc');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Nueva sala');
        return http.Response(
          jsonEncode({'created': true, 'room': _roomJson(id: 9, name: 'Nueva sala')}),
          201,
        );
      });

      final room = await buildService(client, token: 'token-abc').createRoom('Nueva sala');

      expect(room.id, 9);
      expect(room.name, 'Nueva sala');
    });

    test('createRoom sin token válido lanza UnauthorizedException', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'No autorizado'}), 401);
      });

      expect(
        () => buildService(client, token: 'token-vencido').createRoom('Nueva sala'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('updateRoom envía solo los campos provistos (PUT /rooms/<id>)', () async {
      final client = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/rooms/3');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Sala renombrada');
        expect(body['active'], false);
        return http.Response('', 200);
      });

      await buildService(client, token: 'token-abc')
          .updateRoom(3, name: 'Sala renombrada', active: false);
    });

    test('deleteRoom exitoso (DELETE /rooms/<id>)', () async {
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/rooms/3');
        return http.Response('', 200);
      });

      await buildService(client, token: 'token-abc').deleteRoom(3);
    });

    test('deleteRoom fallido lanza RoomException', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'No sos el host'}), 403);
      });

      expect(
        () => buildService(client, token: 'token-abc').deleteRoom(3),
        throwsA(isA<RoomException>()),
      );
    });

    test('processAudio envía el archivo multipart y retorna task_id', () async {
      final tempDir = await Directory.systemTemp.createTemp('speak_english_test');
      final audioFile = File('${tempDir.path}/audio.m4a');
      await audioFile.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() => tempDir.delete(recursive: true));

      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/rooms/4/process-audio');
        // MockClient entrega el cuerpo ya "aplanado" como http.Request, así
        // que en vez de castear a MultipartRequest verificamos el
        // Content-Type y que el campo 'audio' esté en el cuerpo crudo.
        expect(request.headers['content-type'], contains('multipart/form-data'));
        final rawBody = latin1.decode(request.bodyBytes);
        expect(rawBody, contains('name="audio"'));
        return http.Response(
          jsonEncode({
            'message': 'Audio processing started',
            'task_id': 'task-1',
            'saved_file': 'room_4_123_audio.m4a',
          }),
          202,
        );
      });

      final data =
          await buildService(client, token: 'token-abc').processAudio(4, audioFile);

      expect(data['task_id'], 'task-1');
      expect(data['saved_file'], 'room_4_123_audio.m4a');
    });

    test('getTaskStatus retorna el estado de la tarea (GET /tasks/<id>)', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/tasks/task-1');
        return http.Response(
          jsonEncode({
            'task_id': 'task-1',
            'state': 'SUCCESS',
            'result': {'status': 'processed'},
          }),
          200,
        );
      });

      final status = await buildService(client, token: 'token-abc').getTaskStatus('task-1');

      expect(status['state'], 'SUCCESS');
      expect((status['result'] as Map)['status'], 'processed');
    });
  });
}
