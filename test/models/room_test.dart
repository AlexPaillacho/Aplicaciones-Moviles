// Bloque 5 (Taller Semana 13): pruebas de la serialización generada de
// Room/RoomHost, con foco en la divergencia servidor↔cliente documentada
// en room.dart (host anidado -> hostId/hostUsername planos) y en el caso
// host == null (sala sin host resuelto en la respuesta).

import 'package:flutter_test/flutter_test.dart';
import 'package:speak_english/models/room.dart';

void main() {
  final fixedUpdatedAt = DateTime.parse('2026-01-01T00:00:00.000Z');

  group('Room.fromJson', () {
    test('deserializa el host anidado y expone hostId/hostUsername planos', () {
      final json = {
        'id': 1,
        'name': 'Sala 1',
        'active': true,
        'host': {'id': 7, 'username': 'juan'},
        'updated_at': '2026-01-01T00:00:00.000Z',
      };

      final room = Room.fromJson(json);

      expect(room.id, 1);
      expect(room.name, 'Sala 1');
      expect(room.active, isTrue);
      // El JSON trae `host` anidado; el resto de la app sigue leyendo
      // los getters planos sin enterarse de esa forma.
      expect(room.host, isA<RoomHost>());
      expect(room.hostId, 7);
      expect(room.hostUsername, 'juan');
      expect(room.updatedAt, fixedUpdatedAt);
    });

    test('host null es válido (sala sin host resuelto)', () {
      final json = {
        'id': 2,
        'name': 'Sala 2',
        'active': false,
        'host': null,
        'updated_at': '2026-01-01T00:00:00.000Z',
      };

      final room = Room.fromJson(json);

      expect(room.host, isNull);
      expect(room.hostId, isNull);
      expect(room.hostUsername, isNull);
    });
  });

  group('Room.toJson', () {
    test('serializa host anidado con explicitToJson', () {
      final room = Room(
        id: 3,
        name: 'Sala 3',
        active: true,
        host: const RoomHost(id: 9, username: 'ana'),
        updatedAt: fixedUpdatedAt,
      );

      final json = room.toJson();

      expect(json['host'], {'id': 9, 'username': 'ana'});
      expect(json['updated_at'], '2026-01-01T00:00:00.000Z');
      // pendingSync es solo de UI: nunca debe viajar en el JSON.
      expect(json.containsKey('pendingSync'), isFalse);
    });
  });

  group('Room cache map (SQLite, Bloque de Semana 12)', () {
    test('toCacheMap/fromCacheMap aplanan y reconstruyen host', () {
      final room = Room(
        id: 4,
        name: 'Sala 4',
        active: true,
        host: const RoomHost(id: 5, username: 'maria'),
        updatedAt: fixedUpdatedAt,
      );

      final map = room.toCacheMap();
      expect(map['host_id'], 5);
      expect(map['host_username'], 'maria');

      final rebuilt = Room.fromCacheMap(map);
      expect(rebuilt.hostId, 5);
      expect(rebuilt.hostUsername, 'maria');
      expect(rebuilt.updatedAt, fixedUpdatedAt);
    });
  });
}
