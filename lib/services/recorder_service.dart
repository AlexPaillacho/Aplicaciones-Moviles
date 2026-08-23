import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Excepción lanzada cuando no se puede iniciar la grabación (p. ej.
/// permiso de micrófono denegado).
class RecorderException implements Exception {
  const RecorderException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Envuelve el paquete `record` para grabar audio de práctica y
/// guardarlo en un archivo temporal antes de subirlo con
/// `RoomsService.processAudio` (Fase 4). No conoce el backend ni la
/// UI: solo expone `start()`/`stop()`/`dispose()`.
class RecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  /// Pide permiso de micrófono (si hace falta) y empieza a grabar en un
  /// archivo temporal `.m4a`. Lanza `RecorderException` si el permiso
  /// fue denegado.
  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const RecorderException('Permiso de micrófono denegado');
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/practice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
  }

  /// Detiene la grabación y devuelve el archivo `.m4a` resultante, o
  /// `null` si no había ninguna grabación en curso.
  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  /// Libera los recursos del grabador. Se llama desde `dispose()` de la
  /// pantalla; no se espera su Future porque `State.dispose()` es
  /// síncrono.
  void dispose() {
    _recorder.dispose();
  }
}
