// Taller Semana 14 (Fase 4): la ubicación se redondea ANTES de guardarse
// en la caché local y de enviarse al backend.

import 'package:flutter_test/flutter_test.dart';

import 'package:speak_english/models/user_location.dart';

void main() {
  group('UserLocation.approximate', () {
    test('redondea las coordenadas a 2 decimales (~1,1 km)', () {
      final location = UserLocation.approximate(
        latitude: 12.34567,
        longitude: -76.54321,
      );

      expect(UserLocation.precisionDecimals, 2);
      expect(location.latitude, 12.35);
      expect(location.longitude, -76.54);
    });

    test('conserva la fecha de captura indicada', () {
      final capturedAt = DateTime.utc(2026, 9, 20, 12, 30);

      final location = UserLocation.approximate(
        latitude: 1.0,
        longitude: 2.0,
        capturedAt: capturedAt,
      );

      expect(location.capturedAt, capturedAt);
    });

    test('usa la hora actual si no se indica fecha de captura', () {
      final before = DateTime.now();

      final location = UserLocation.approximate(latitude: 1.0, longitude: 2.0);

      expect(location.capturedAt.isBefore(before), isFalse);
    });
  });

  group('UserLocation.hasSameCoordinatesAs', () {
    test('dos posiciones cercanas caen en la misma cuadrícula tras redondear', () {
      final a = UserLocation.approximate(latitude: 12.3412, longitude: -76.5411);
      final b = UserLocation.approximate(latitude: 12.3449, longitude: -76.5449);

      expect(a.hasSameCoordinatesAs(b), isTrue);
    });

    test('posiciones en otra cuadrícula se consideran distintas', () {
      final a = UserLocation.approximate(latitude: 12.34, longitude: -76.54);
      final b = UserLocation.approximate(latitude: 12.40, longitude: -76.54);

      expect(a.hasSameCoordinatesAs(b), isFalse);
    });
  });

  group('CachedLocation', () {
    test('con posición está disponible', () {
      final cached = CachedLocation(
        location: UserLocation.approximate(latitude: 1.0, longitude: 2.0),
        updatedAt: DateTime.now(),
      );

      expect(cached.isAvailable, isTrue);
    });

    test('sin posición representa el estado "sin ubicación"', () {
      final cached = CachedLocation(updatedAt: DateTime.now());

      expect(cached.isAvailable, isFalse);
      expect(cached.location, isNull);
    });
  });
}
