import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:speak_english/services/recorder_service.dart';

RecordedAudio _audio({
  int sizeBytes = 20000,
  Duration duration = const Duration(seconds: 3),
  double peakDb = -20,
}) {
  return RecordedAudio(
    file: File('practice.m4a'),
    duration: duration,
    sizeBytes: sizeBytes,
    peakDb: peakDb,
  );
}

void main() {
  group('RecordedAudio.problem', () {
    test('una grabación normal es válida', () {
      expect(_audio().problem, isNull);
    });

    test('un archivo vacío se rechaza', () {
      expect(_audio(sizeBytes: 0).problem, contains('vacía'));
    });

    test('una grabación de menos de un segundo se rechaza', () {
      final audio = _audio(duration: const Duration(milliseconds: 400));
      expect(audio.problem, contains('corta'));
    });

    test('una grabación sin sonido (micrófono ocupado) se rechaza', () {
      expect(_audio(peakDb: -160).problem, contains('No se captó sonido'));
    });
  });
}
