import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'permission_service.dart';

/// Excepción lanzada cuando no se puede iniciar la grabación (p. ej.
/// permiso de micrófono denegado).
///
/// [permissionStatus] es `null` para errores que no son de permisos (ej.
/// el propio `record` falló al escribir el archivo); cuando sí es un
/// problema de permiso, la UI usa este campo para decidir si mostrar
/// "pedir de nuevo" o "Abrir Ajustes" (`permanentlyDenied`), en vez de
/// tener que parsear `message`.
class RecorderException implements Exception {
  const RecorderException(this.message, {this.permissionStatus});
  final String message;
  final AppPermissionStatus? permissionStatus;

  @override
  String toString() => message;
}

/// Resultado de una grabación terminada, con lo necesario para decidir si
/// vale la pena enviarla al backend.
class RecordedAudio {
  const RecordedAudio({
    required this.file,
    required this.duration,
    required this.sizeBytes,
    required this.peakDb,
  });

  /// Duración mínima para considerar que hubo una práctica real.
  static const Duration minDuration = Duration(seconds: 1);

  /// Tamaño mínimo de un `.m4a` con contenido. Un archivo vacío o con solo
  /// la cabecera del contenedor pesa mucho menos.
  static const int minSizeBytes = 1024;

  /// Nivel pico (dBFS) por debajo del cual se considera que el micrófono
  /// no captó sonido (silencio digital). La voz normal supera ampliamente
  /// este umbral; un micrófono ocupado por otra app (llamada, grabadora)
  /// se queda en el piso del rango.
  static const double silenceThresholdDb = -50;

  final File file;
  final Duration duration;
  final int sizeBytes;

  /// Nivel pico medido durante la grabación, en dBFS (0 es el máximo).
  final double peakDb;

  /// Mensaje para el usuario si la grabación no sirve; `null` si es válida.
  String? get problem {
    if (sizeBytes < minSizeBytes) {
      return 'La grabación quedó vacía. Cierra otras apps que usen el '
          'micrófono (llamadas, videollamadas) e inténtalo de nuevo.';
    }
    if (duration < minDuration) {
      return 'La grabación es demasiado corta. Habla al menos un segundo.';
    }
    if (peakDb < silenceThresholdDb) {
      return 'No se captó sonido. Revisa que el micrófono no esté siendo '
          'usado por otra app (llamada o videollamada) e inténtalo de nuevo.';
    }
    return null;
  }
}

/// Envuelve el paquete `record` para grabar audio de práctica y
/// guardarlo en un archivo temporal antes de subirlo con
/// `RoomsRemoteSource.processAudio`. No conoce el backend ni la UI: solo
/// expone `start()`/`stop()`/`dispose()`.
class RecorderService {
  RecorderService({PermissionService? permissionService})
      : _permissionService = permissionService ?? PermissionService();

  /// Configuración explícita (en vez de los valores por defecto del
  /// paquete) para que el formato no dependa de la versión: AAC-LC en
  /// mono a 44,1 kHz, suficiente para voz y compatible con cualquier
  /// reproductor.
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 128000,
    sampleRate: 44100,
    numChannels: 1,
  );

  static const Duration _amplitudeInterval = Duration(milliseconds: 200);
  static const double _silenceFloorDb = -160;

  final AudioRecorder _recorder = AudioRecorder();
  final PermissionService _permissionService;

  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final Stopwatch _stopwatch = Stopwatch();
  double _peakDb = _silenceFloorDb;

  /// Pide permiso de micrófono (si hace falta) y empieza a grabar en un
  /// archivo temporal `.m4a`. Lanza [RecorderException] si el permiso no
  /// quedó concedido, distinguiendo los estados vía
  /// [RecorderException.permissionStatus] (la UI decide qué mostrar según
  /// ese estado, en vez de esta capa saber de diálogos).
  Future<void> start() async {
    final status = await _permissionService.requestMicrophone();
    if (status != AppPermissionStatus.granted) {
      throw RecorderException(_messageFor(status), permissionStatus: status);
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/practice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    _peakDb = _silenceFloorDb;
    await _recorder.start(_config, path: path);
    _stopwatch
      ..reset()
      ..start();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(_amplitudeInterval)
        .listen(_trackPeak);
  }

  /// Detiene la grabación y devuelve el archivo resultante con sus
  /// métricas, o `null` si no había ninguna grabación en curso. No decide
  /// si la grabación es válida: eso lo expone [RecordedAudio.problem].
  Future<RecordedAudio?> stop() async {
    _stopwatch.stop();
    await _cancelAmplitudeTracking();

    final path = await _recorder.stop();
    if (path == null) return null;

    final file = File(path);
    final sizeBytes = await file.exists() ? await file.length() : 0;
    return RecordedAudio(
      file: file,
      duration: _stopwatch.elapsed,
      sizeBytes: sizeBytes,
      peakDb: _peakDb,
    );
  }

  /// Libera los recursos del grabador. Se llama desde `dispose()` de la
  /// pantalla; no se espera su Future porque `State.dispose()` es
  /// síncrono.
  void dispose() {
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
  }

  void _trackPeak(Amplitude amplitude) {
    if (amplitude.current > _peakDb) _peakDb = amplitude.current;
  }

  Future<void> _cancelAmplitudeTracking() async {
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
  }

  String _messageFor(AppPermissionStatus status) {
    switch (status) {
      case AppPermissionStatus.permanentlyDenied:
        return 'Denegaste el micrófono permanentemente. Actívalo desde '
            'los ajustes de la app.';
      case AppPermissionStatus.restricted:
        return 'El micrófono no está disponible en este dispositivo.';
      case AppPermissionStatus.denied:
      case AppPermissionStatus.granted:
        // granted nunca llega acá (ver el `if` en start()), pero el
        // switch debe ser exhaustivo.
        return 'Permiso de micrófono denegado';
    }
  }
}
