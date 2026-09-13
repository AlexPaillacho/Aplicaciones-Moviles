// Bloque 5 (Taller Semana 13): prueba de la serialización generada de
// User. Sin divergencias de nomenclatura que cubrir (los 3 campos
// coinciden 1:1 con el backend), así que solo se verifica el
// round-trip fromJson/toJson.

import 'package:flutter_test/flutter_test.dart';
import 'package:speak_english/models/user.dart';

void main() {
  group('User', () {
    test('fromJson/toJson hacen round-trip sin pérdida de datos', () {
      final json = {'id': 1, 'username': 'juan', 'email': 'juan@example.com'};

      final user = User.fromJson(json);

      expect(user.id, 1);
      expect(user.username, 'juan');
      expect(user.email, 'juan@example.com');
      expect(user.toJson(), json);
    });
  });
}
