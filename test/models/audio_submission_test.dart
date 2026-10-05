import 'package:flutter_test/flutter_test.dart';
import 'package:speak_english/models/audio_submission.dart';
import 'package:speak_english/screens/rooms/submissions_screen.dart';

Map<String, dynamic> _json({String status = 'SUCCESS'}) => {
      'id': 7,
      'room_id': 4,
      'user_id': 1,
      'task_id': 'abc-123',
      'status': status,
      'result': null,
      'created_at': '2026-10-01T15:30:00Z',
    };

void main() {
  group('AudioSubmission.fromJson', () {
    test('lee los campos y convierte la fecha UTC a hora local', () {
      final submission = AudioSubmission.fromJson(_json());

      expect(submission.id, 7);
      expect(submission.roomId, 4);
      expect(submission.taskId, 'abc-123');
      expect(submission.createdAt.isUtc, isFalse);
      expect(
        submission.createdAt.toUtc(),
        DateTime.utc(2026, 10, 1, 15, 30),
      );
    });

    test('todo envío se muestra como "Enviado" (el audio ya está guardado)', () {
      for (final status in ['SUCCESS', 'FAILURE', 'PENDING', 'STARTED']) {
        expect(
          AudioSubmission.fromJson(_json(status: status)).statusLabel,
          'Enviado',
        );
      }
    });
  });

  group('SubmissionsPage.hasMore', () {
    test('hay más páginas solo mientras page < totalPages', () {
      const first = SubmissionsPage(
        submissions: [],
        page: 1,
        totalPages: 2,
        total: 12,
      );
      const last = SubmissionsPage(
        submissions: [],
        page: 2,
        totalPages: 2,
        total: 12,
      );

      expect(first.hasMore, isTrue);
      expect(last.hasMore, isFalse);
    });
  });

  test('la duración se lee del JSON y se formatea', () {
    final withDuration =
        AudioSubmission.fromJson({..._json(), 'duration_seconds': 12});
    expect(withDuration.durationSeconds, 12);
    expect(withDuration.durationLabel, '12 s');

    expect(AudioSubmission.fromJson(_json()).durationLabel, '—');
    expect(formatAudioDuration(65), '1 min 05 s');
    expect(formatAudioDuration(0), '0 s');
  });

  test('formatSubmissionDate usa dd/MM/yyyy HH:mm con ceros', () {
    expect(
      formatSubmissionDate(DateTime(2026, 3, 5, 9, 4)),
      '05/03/2026 09:04',
    );
  });
}
