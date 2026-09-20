import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'permission_service.dart';

/// Excepción lanzada cuando no se puede iniciar la grabación (p. ej.
/// permiso de micrófono denegado).
///
/// Fase 3 (Taller Semana 14): [permissionStatus] es `null` para errores
/// que no son de permisos (ej. el propio `record` falló al escribir el
/// archivo); cuando sí es un problema de permiso, la UI usa este campo
/// para decidir si mostrar "pedir de nuevo" o "Abrir Ajustes"
/// (`permanentlyDenied`), en vez de tener que parsear `message`.
class RecorderException implements Exception {
  const RecorderException(this.message, {this.permissionStatus});
  final String message;
  final AppPermissionStatus? permissionStatus;

  @override
  String toString() => message;
}

/// Envuelve el paquete `record` para grabar audio de práctica y
/// guardarlo en un archivo temporal antes de subirlo con
/// `RoomsRemoteSource.processAudio` (Fase 4). No conoce el backend ni la
/// UI: solo expone `start()`/`stop()`/`dispose()`.
class RecorderService {
  RecorderService({PermissionService? permissionService})
      : _permissionService = permissionService ?? PermissionService();

  final AudioRecorder _recorder = AudioRecorder();
  final PermissionService _permissionService;

  /// Pide permiso de micrófono (si hace falta) y empieza a grabar en un
  /// archivo temporal `.m4a`. Lanza `RecorderException` si el permiso
  /// no quedó concedido, distinguiendo los 4 estados vía
  /// `RecorderException.permissionStatus` (Fase 3: la UI decide qué
  /// mostrar según ese estado, en vez de esta capa saber de diálogos).
  Future<void> start() async {
    final status = await _permissionService.requestMicrophone();
    if (status != AppPermissionStatus.granted) {
      throw RecorderException(_messageFor(status), permissionStatus: status);
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
