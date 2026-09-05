import 'package:flutter/foundation.dart';

import '../models/room.dart';
import 'api_service.dart';
import 'local_db_service.dart';
import 'rooms_service.dart';

/// Procesa la cola de operaciones offline (`pending_room_ops`).
///
/// Se dispara desde tres lugares (ver `rooms_provider.dart` y
/// `app.dart`): al reconectar (`ConnectivityService.onConnectivityRestored`),
/// al hacer pull-to-refresh, y justo después de encolar una operación si
/// en ese momento ya hay conexión.
///
/// Reintentos: cada operación se reintenta hasta [maxAttempts] veces con
/// espera creciente (2s, 4s, 8s, 16s, ...) SOLO cuando el fallo es del
/// servidor (ej. 500) — no tiene sentido reintentar en caliente si el
/// fallo es de red (`NetworkException`): ahí se corta el procesamiento
/// de toda la cola de inmediato y se espera a la próxima reconexión.
class SyncService {
  SyncService({RoomsService? roomsService, LocalDbService? localDb})
      : _roomsService = roomsService ?? RoomsService(ApiService()),
        _localDb = localDb ?? LocalDbService.instance;

  final RoomsService _roomsService;
  final LocalDbService _localDb;

  static const int maxAttempts = 5;

  bool _isSyncing = false;

  /// Procesa toda la cola pendiente, en orden FIFO. Devuelve `true` si
  /// se sincronizó al menos una operación (para que el provider sepa que
  /// vale la pena refrescar la lista desde la caché).
  Future<bool> processPendingQueue() async {
    if (_isSyncing) return false; // evita procesar la cola en paralelo
    _isSyncing = true;
    var syncedAny = false;

    try {
      final ops = await _localDb.getPendingOperations();

      for (final op in ops) {
        if (op['status'] == 'failed') continue; // requiere reintento manual

        final ok = await _processOperationWithRetry(op);
        if (ok) {
          syncedAny = true;
        } else {
          // Si un batazo de la cola no se pudo enviar por falta de red,
          // asumimos que el resto tampoco podrá: cortamos acá y
          // esperamos a la próxima reconexión en vez de seguir fallando
          // operación por operación.
          break;
        }
      }
    } finally {
      _isSyncing = false;
    }

    return syncedAny;
  }

  /// Intenta [op] hasta [maxAttempts] veces con espera creciente.
  /// Devuelve `false` únicamente cuando el motivo fue falta de conexión
  /// (para cortar el resto de la cola); cualquier otro desenlace —éxito,
  /// conflicto resuelto, o agotar los reintentos— devuelve `true` porque
  /// esa operación puntual ya quedó resuelta (sincronizada, resuelta por
  /// conflicto, o marcada `failed` para reintento manual).
  Future<bool> _processOperationWithRetry(Map<String, Object?> op) async {
    final clientOpId = op['client_op_id'] as String;
    var attempt = (op['attempt_count'] as int?) ?? 0;

    while (attempt < maxAttempts) {
      try {
        await _applyOperation(op);
        await _localDb.deleteOperation(clientOpId);
        return true;
      } on RoomConflictException catch (e) {
        await _resolveConflict(op, e.serverRoom);
        return true;
      } on NetworkException {
        // Sin conexión real (no solo el servidor caído): no reintentamos
        // en caliente, esperamos la próxima señal de reconexión.
        return false;
      } catch (_) {
        attempt += 1;
        await _localDb.markAttempt(clientOpId, failed: attempt >= maxAttempts);
        if (attempt >= maxAttempts) {
          return true; // se dio por vencida esta operación; sigue la cola
        }
        final backoff = Duration(seconds: 1 << attempt); // 2s, 4s, 8s, 16s...
        await Future.delayed(backoff);
      }
    }
    return true;
  }

  Future<void> _applyOperation(Map<String, Object?> op) async {
    final opType = op['op_type'] as String;

    if (opType == 'create') {
      final localTempId = op['local_temp_id'] as int;
      final name = op['name'] as String;
      final room = await _roomsService.createRoom(name);
      await _localDb.replaceTempRoomId(localTempId, room);
      return;
    }

    if (opType == 'update') {
      final roomId = op['room_id'] as int;
      final name = op['name'] as String?;
      final activeRaw = op['active'] as int?;
      final baseUpdatedAt = op['base_updated_at'] as String?;
      final room = await _roomsService.updateRoom(
        roomId,
        name: name,
        active: activeRaw == null ? null : activeRaw == 1,
        expectedUpdatedAt: baseUpdatedAt,
      );
      await _localDb.upsertRoom(room);
      return;
    }

    debugPrint('[SyncService] Tipo de operación desconocido: $opType');
  }

  /// El servidor ganó el conflicto (ver `expected_updated_at` en el
  /// backend): descartamos la edición local, nos quedamos con la
  /// versión del servidor y sacamos la operación de la cola. Esto es el
  /// trade-off explícito que documenta el taller: la edición offline del
  /// usuario se pierde silenciosamente en favor de lo último escrito en
  /// el servidor.
  Future<void> _resolveConflict(Map<String, Object?> op, Room serverRoom) async {
    await _localDb.upsertRoom(serverRoom);
    final clientOpId = op['client_op_id'] as String;
    await _localDb.deleteOperation(clientOpId);
    debugPrint(
      '[SyncService] Conflicto en room ${serverRoom.id}: se descartó la '
      'edición local, gana la versión del servidor (updated_at=${serverRoom.updatedAt}).',
    );
  }
}
