/// Un envío de audio de práctica, tal como lo devuelve
/// `GET /rooms/<id>/submissions` (persistido en la base de datos).
class AudioSubmission {
  const AudioSubmission({
    required this.id,
    required this.roomId,
    required this.taskId,
    required this.status,
    required this.createdAt,
    this.savedFilename,
    this.durationSeconds,
  });

  factory AudioSubmission.fromJson(Map<String, dynamic> json) {
    return AudioSubmission(
      id: json['id'] as int,
      roomId: json['room_id'] as int,
      taskId: json['task_id'] as String,
      status: json['status'] as String,
      savedFilename: json['saved_filename'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      // El backend manda UTC con sufijo 'Z'; se muestra en hora local.
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final int id;
  final int roomId;
  final String taskId;

  /// Estado espejo de Celery: PENDING | STARTED | SUCCESS | FAILURE.
  final String status;
  final DateTime createdAt;

  /// Nombre con el que el backend guardó el audio (el audio siempre se
  /// guarda, aunque el procesamiento posterior falle).
  final String? savedFilename;

  /// Duración de la grabación en segundos (`null` en envíos antiguos).
  final int? durationSeconds;

  /// "12 s" o "1 min 05 s"; "—" si no se conoce.
  String get durationLabel => formatAudioDuration(durationSeconds);

  bool get isProcessed => status == 'SUCCESS';
  bool get isFailed => status == 'FAILURE';

  /// Texto corto para la UI. El audio ya está guardado en el servidor
  /// desde el momento del envío; el procesamiento en segundo plano es un
  /// detalle interno (simulado), así que al usuario siempre se le muestra
  /// "Enviado", sin estados de error ni "procesando".
  String get statusLabel => 'Enviado';
}

/// Una página del historial de envíos con sus metadatos de paginación.
class SubmissionsPage {
  const SubmissionsPage({
    required this.submissions,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final List<AudioSubmission> submissions;
  final int page;
  final int totalPages;
  final int total;

  bool get hasMore => page < totalPages;
}

/// Formatea segundos como "45 s" o "1 min 05 s". `null` -> "—".
String formatAudioDuration(int? seconds) {
  if (seconds == null) return '—';
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes min $rest s';
}
