import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/room.dart';
import '../models/user_location.dart';
import '../services/api_service.dart';
import 'rooms_local_source.dart';
import 'rooms_remote_source.dart';

/// Resultado de un intento de `RoomsRepository.refresh()`.
///
/// `RoomsProvider` traduce esto directamente a sus banderas de estado
/// (`isOffline`, `errorMessage`) sin necesitar saber si el fallo vino de
/// HTTP, del backend, o de ningún lado (éxito).
class RoomsRefreshOutcome {
  const RoomsRefreshOutcome({this.isOffline = false, this.errorMessage});

  /// Sin conexión (o el backend no respondió a tiempo): la UI debe
  /// seguir mostrando la caché y prender el aviso de modo offline.
  final bool isOffline;

  /// Mensaje de error a mostrar, si el backend respondió algo distinto
  /// de éxito (`null` si no hubo error).
  final String? errorMessage;
}

/// Resultado de `RoomsRepository.trySyncPending()`.
///
/// `RoomsProvider` lo usa para saber si hay que refrescar la lista
/// (`syncedAny`) y, si el backend rechazó alguna operación encolada con
/// un 422, para mostrarle ese mensaje al usuario (`errorMessage`) en vez
/// de dejarlo solo en el log.
class RoomsSyncOutcome {
  const RoomsSyncOutcome({this.syncedAny = false, this.errorMessage});
  final bool syncedAny;
  final String? errorMessage;
}

/// Resultado interno de procesar una operación de la cola.
class _OperationResult {
  const _OperationResult({required this.resolved, this.errorMessage});

  /// `true`: la operación quedó resuelta (éxito, conflicto resuelto,
  /// rechazada por validación, o reintentos agotados) y hay que seguir
  /// con la próxima de la cola. `false`: no hay conexión real, hay que
  /// cortar el procesamiento del resto de la cola.
  final bool resolved;

  /// Mensaje del backend si la operación fue rechazada con 422.
  final String? errorMessage;
}

/// Repositorio de salas (rooms): única puerta de entrada a los datos de
/// rooms para el resto de la app.
///
/// Taller Semana 13 (Bloque 6): capa "repositorio" de la nueva
/// arquitectura de datos (remoto / local / repositorio). Combina
/// `RoomsRemoteSource` (backend) y `RoomsLocalSource` (SQLite) e
/// implementa la estrategia offline-first completa: lecturas desde
/// caché, escrituras optimistas + cola, y la sincronización en segundo
/// plano con reintentos (antes vivía separada en `SyncService`).
///
/// `RoomsProvider` (estado/UI) solo conoce esta clase — no le llega
/// ninguna referencia a `RoomsRemoteSource` ni `RoomsLocalSource`, así
/// que no tiene forma de enterarse de si un dato vino de HTTP o de
/// SQLite.
class RoomsRepository {
  RoomsRepository({RoomsRemoteSource? remote, RoomsLocalSource? local})
      : _remote = remote ?? RoomsRemoteSource(ApiService.instance),
        _local = local ?? RoomsLocalSource.instance;

  final RoomsRemoteSource _remote;
  final RoomsLocalSource _local;
  final _uuid = const Uuid();

  /// Reintentos de sincronización: hasta [maxAttempts] veces con espera
  /// creciente (2s, 4s, 8s, 16s, ...), SOLO cuando el fallo es del
  /// servidor (ej. 500) — no tiene sentido reintentar en caliente si el
  /// fallo es de red (`NetworkException`): ahí se corta el
  /// procesamiento de toda la cola de inmediato y se espera a la
  /// próxima reconexión.
  ///
  /// Bloque 7: este backoff con reintentos SOLO aplica a operaciones
  /// idempotentes (`update`, un `PUT /rooms/<id>`). A un `create` (POST,
  /// NO idempotente, y el backend no deduplica por `client_op_id` pese a
  /// que existe desde Semana 12 — ver `_processOperationWithRetry`) se le
  /// da como máximo un único intento automático, para no arriesgarse a
  /// crear la sala duplicada si el primer POST sí llegó a impactar el
  /// servidor pero la respuesta se perdió en el camino.
  static const int maxAttempts = 5;

  bool _isSyncing = false;

  // ===== Lecturas (siempre desde caché) =====

  Future<List<Room>> getCachedRooms() => _local.getCachedRooms();

  Future<DateTime?> getLastSyncedAt() => _local.getLastSyncedAt();

  Future<int> getPendingCount() => _local.countPending();

  // ===== Ubicación (Taller Semana 14, Fase 4) =====

  /// Última ubicación guardada localmente (posición aproximada o el
  /// estado "sin ubicación"); `null` si nunca se guardó nada.
  Future<CachedLocation?> getCachedLocation() => _local.getCachedLocation();

  /// Guarda en la caché local la ubicación aproximada del usuario, o el
  /// estado "sin ubicación" si [location] es `null` (permiso no
  /// concedido: además se BORRAN las coordenadas anteriores, para no
  /// volver a enviar una posición vieja).
  ///
  /// Devuelve `true` si la ubicación ENVIABLE cambió (había otra
  /// posición o no había ninguna): quien llama usa eso para decidir si
  /// vale la pena refrescar la lista y así mandarle la nueva ubicación
  /// al backend. Guardar el estado "sin ubicación" devuelve siempre
  /// `false`.
  Future<bool> saveLocation(UserLocation? location) async {
    final cached = await _local.getCachedLocation();

    if (location == null) {
      // Evita reescribir la fila si ya estaba en "sin ubicación".
      if (cached == null || cached.isAvailable) {
        await _local.saveLocationUnavailable();
        debugPrint('[RoomsRepository] Sin ubicación: se guardó el estado '
            '"sin ubicación" y se borraron las coordenadas locales.');
      }
      return false;
    }

    final previous = cached?.location;
    await _local.saveLocation(location);
    debugPrint('[RoomsRepository] Ubicación aproximada guardada en la '
        'caché local: ${location.latitude}, ${location.longitude}');
    return previous == null || !previous.hasSameCoordinatesAs(location);
  }

  /// Ubicación que se puede enviar al backend ahora mismo: la última
  /// posición conocida, o `null` si no hay (nunca se obtuvo, o el
  /// estado guardado es "sin ubicación"). Es "best effort": si la caché
  /// falla al leerse, se sigue sin ubicación en vez de romper el
  /// listado o la creación de salas.
  Future<UserLocation?> _sendableLocation() async {
    try {
      return (await _local.getCachedLocation())?.location;
    } catch (_) {
      return null;
    }
  }

  // ===== Refresh contra el backend =====

  /// `GET /rooms/list`, con la caché como fuente de verdad para la UI:
  /// si tiene éxito, actualiza `rooms_cache` y `last_synced_at`; si
  /// falla, la caché existente queda intacta y el resultado le dice al
  /// llamador qué pasó (sin conexión / error del backend / éxito).
  Future<RoomsRefreshOutcome> refresh() async {
    try {
      // Fase 4: si hay ubicación aproximada guardada, viaja con la
      // petición (opcional; sin ella el listado funciona igual).
      final location = await _sendableLocation();
      final serverRooms = await _listRoomsWithRetry(location);
      await _local.upsertServerRooms(serverRooms);
      await _local.setLastSyncedAt(DateTime.now());
      return const RoomsRefreshOutcome();
    } on UnauthorizedException {
      // Logout y navegación ya ocurren de forma centralizada en
      // ApiService.onUnauthorized.
      return const RoomsRefreshOutcome();
    } on NoConnectionException {
      return const RoomsRefreshOutcome(isOffline: true);
    } on NetworkException catch (e) {
      // Timeout o servidor caído: ya se intentó una vez más en
      // `_listRoomsWithRetry` y siguió fallando. Se muestra como error
      // (con botón "Reintentar" manual vía StatusView), a diferencia de
      // "sin conexión" que es un modo silencioso de solo-caché.
      return RoomsRefreshOutcome(errorMessage: e.message);
    } on RoomException catch (e) {
      return RoomsRefreshOutcome(errorMessage: e.message);
    } catch (_) {
      return const RoomsRefreshOutcome(errorMessage: 'Ocurrió un error inesperado');
    }
  }

  /// `GET /rooms/list` es idempotente (Bloque 7): a diferencia de un
  /// `create`, reintentarlo automáticamente no arriesga duplicar nada.
  /// Un único reintento inmediato absorbe un timeout o una caída
  /// puntual del servidor sin que el usuario tenga que tocar
  /// "Reintentar" él mismo; si el segundo intento también falla, se le
  /// deja la decisión al llamador (`refresh()` cae a la caché + botón
  /// manual). No se reintenta ante [NoConnectionException]: sin ninguna
  /// interfaz de red activa, reintentar de inmediato no cambia nada.
  Future<List<Room>> _listRoomsWithRetry(UserLocation? location) async {
    try {
      return await _remote.listRooms(location: location);
    } on RequestTimeoutException {
      return _remote.listRooms(location: location);
    } on ServerUnavailableException {
      return _remote.listRooms(location: location);
    }
  }

  // ===== Escrituras optimistas =====

  /// Crea una sala de forma optimista: la aplica de inmediato en la
  /// caché local con un id temporal negativo (para que aparezca en la
  /// lista al toque) y la encola para sincronizar. `hostId`/
  /// `hostUsername` son los del usuario actual, para que la card
  /// muestre el host correcto mientras la sala todavía no tiene id real
  /// del servidor.
  ///
  /// Fase 4: si hay ubicación aproximada disponible, se guarda junto a la
  /// operación encolada. Así se envía la ubicación del momento en que el
  /// usuario creó la sala aunque se sincronice mucho después (offline).
  Future<void> createOptimistic(String name, {int? hostId, String? hostUsername}) async {
    final tempId = -DateTime.now().microsecondsSinceEpoch;
    final optimisticRoom = Room(
      id: tempId,
      name: name,
      active: true,
      host: (hostId != null && hostUsername != null)
          ? RoomHost(id: hostId, username: hostUsername)
          : null,
      updatedAt: DateTime.now(),
    );

    final location = await _sendableLocation();

    await _local.upsertRoom(optimisticRoom);
    await _local.enqueueCreate(
      clientOpId: _uuid.v4(),
      localTempId: tempId,
      name: name,
      latitude: location?.latitude,
      longitude: location?.longitude,
    );
  }

  /// Edita una sala de forma optimista. `room` debe ser la instancia tal
  /// como está en `RoomsProvider.rooms` ahora mismo: su `updatedAt` es
  /// la base con la que el servidor detectará (o no) un conflicto al
  /// sincronizar.
  Future<void> updateOptimistic(Room room, {String? name, bool? active}) async {
    final optimisticRoom = room.copyWith(
      name: name,
      active: active,
      updatedAt: DateTime.now(),
    );

    await _local.upsertRoom(optimisticRoom);
    await _local.enqueueUpdate(
      clientOpId: _uuid.v4(),
      roomId: room.id,
      name: name,
      active: active,
      baseUpdatedAt: room.updatedAt.toIso8601String(),
    );
  }

  // ===== Sincronización de la cola pendiente (antes SyncService) =====

  /// Procesa toda la cola pendiente, en orden FIFO. Devuelve `true` si
  /// se sincronizó al menos una operación (para que `RoomsProvider` sepa
  /// que vale la pena refrescar la lista desde la caché).
  Future<RoomsSyncOutcome> trySyncPending() async {
    if (_isSyncing) return const RoomsSyncOutcome(); // evita procesar la cola en paralelo
    _isSyncing = true;
    var syncedAny = false;
    String? validationError;

    try {
      final ops = await _local.getPendingOperations();

      for (final op in ops) {
        if (op['status'] == 'failed') continue; // requiere reintento manual

        final result = await _processOperationWithRetry(op);
        if (result.resolved) {
          syncedAny = true;
          // Nos quedamos con el primer error de validación de esta
          // pasada (alcanza para avisarle al usuario qué operación
          // rebotó; si hay varias, el resto queda igual disponible en
          // el log).
          validationError ??= result.errorMessage;
        } else {
          // Si una operación de la cola no se pudo enviar por falta de
          // red, asumimos que el resto tampoco podrá: cortamos acá y
          // esperamos a la próxima reconexión en vez de seguir fallando
          // operación por operación.
          break;
        }
      }
    } finally {
      _isSyncing = false;
    }

    return RoomsSyncOutcome(syncedAny: syncedAny, errorMessage: validationError);
  }

  /// Intenta [op] hasta [maxAttempts] veces con espera creciente — pero
  /// SOLO si [op] es idempotente (Bloque 7). Devuelve `false`
  /// únicamente cuando el motivo fue falta de conexión (para cortar el
  /// resto de la cola); cualquier otro desenlace —éxito, conflicto
  /// resuelto, o agotar los intentos permitidos— devuelve `true` porque
  /// esa operación puntual ya quedó resuelta (sincronizada, resuelta por
  /// conflicto, o marcada `failed` para reintento manual).
  Future<_OperationResult> _processOperationWithRetry(Map<String, Object?> op) async {
    final clientOpId = op['client_op_id'] as String;

    // `update` es un PUT con id: reenviarlo no tiene efectos distintos
    // de enviarlo una sola vez, así que se le da el backoff completo. Un
    // `create` es un POST no idempotente — el backend no deduplica por
    // `client_op_id` (ver Bloque 6) — así que solo se le da UN intento
    // automático; si falla por algo que no sea falta de red, se marca
    // `failed` de inmediato en vez de reintentarlo solo, para no arriesgar
    // una sala duplicada.
    final opType = op['op_type'] as String;
    final attemptsAllowed = opType == 'update' ? maxAttempts : 1;

    var attempt = (op['attempt_count'] as int?) ?? 0;

    while (attempt < attemptsAllowed) {
      try {
        await _applyOperation(op);
        await _local.deleteOperation(clientOpId);
        return const _OperationResult(resolved: true);
      } on RoomConflictException catch (e) {
        await _resolveConflict(op, e.serverRoom);
        return const _OperationResult(resolved: true);
      } on NetworkException {
        // Sin conexión real (no solo el servidor caído): no
        // reintentamos en caliente, esperamos la próxima señal de
        // reconexión.
        return const _OperationResult(resolved: false);
      } on ValidationException catch (e) {
        // 422: el problema es el contenido de la operación (ej. un
        // `name` que el backend rechazó), no algo transitorio.
        // Reintentar el mismo payload nunca lo arregla.
        if (opType == 'create') {
          // La sala optimista (id temporal) nunca fue válida para el
          // servidor: la sacamos de la caché en vez de dejarla
          // "fantasma" en la lista, y descartamos la operación (no
          // tiene sentido reintentar el mismo payload).
          final localTempId = op['local_temp_id'] as int?;
          if (localTempId != null) {
            await _local.deleteRoom(localTempId);
          }
          await _local.deleteOperation(clientOpId);
        } else {
          // En un `update` sí conviene dejarla para reintento manual:
          // la sala original sigue viva, solo falló la edición.
          await _local.markAttempt(clientOpId, failed: true);
        }
        debugPrint('[RoomsRepository] Operación $clientOpId inválida: ${e.message}');
        return _OperationResult(resolved: true, errorMessage: e.message);
      } catch (_) {
        attempt += 1;
        final giveUp = attempt >= attemptsAllowed;
        await _local.markAttempt(clientOpId, failed: giveUp);
        if (giveUp) {
          return const _OperationResult(resolved: true); // se dio por vencida; sigue la cola
        }
        final backoff = Duration(seconds: 1 << attempt); // 2s, 4s, 8s, 16s...
        await Future.delayed(backoff);
      }
    }
    return const _OperationResult(resolved: true);
  }

  Future<void> _applyOperation(Map<String, Object?> op) async {
    final opType = op['op_type'] as String;

    if (opType == 'create') {
      final localTempId = op['local_temp_id'] as int;
      final name = op['name'] as String;

      // Fase 4: ubicación guardada al encolar la creación (null si en
      // ese momento no había ubicación disponible).
      final latitude = (op['latitude'] as num?)?.toDouble();
      final longitude = (op['longitude'] as num?)?.toDouble();
      final location = (latitude != null && longitude != null)
          ? UserLocation(
              latitude: latitude,
              longitude: longitude,
              capturedAt: DateTime.tryParse(op['created_at'] as String? ?? '') ??
                  DateTime.now(),
            )
          : null;

      final room = await _remote.createRoom(name, location: location);
      await _local.replaceTempRoomId(localTempId, room);
      return;
    }

    if (opType == 'update') {
      final roomId = op['room_id'] as int;
      final name = op['name'] as String?;
      final activeRaw = op['active'] as int?;
      final baseUpdatedAt = op['base_updated_at'] as String?;
      final room = await _remote.updateRoom(
        roomId,
        name: name,
        active: activeRaw == null ? null : activeRaw == 1,
        expectedUpdatedAt: baseUpdatedAt,
      );
      await _local.upsertRoom(room);
      return;
    }

    debugPrint('[RoomsRepository] Tipo de operación desconocido: $opType');
  }

  /// El servidor ganó el conflicto (ver `expected_updated_at` en el
  /// backend): descartamos la edición local, nos quedamos con la
  /// versión del servidor y sacamos la operación de la cola. Esto es el
  /// trade-off explícito que documenta el taller: la edición offline del
  /// usuario se pierde silenciosamente en favor de lo último escrito en
  /// el servidor.
  Future<void> _resolveConflict(Map<String, Object?> op, Room serverRoom) async {
    await _local.upsertRoom(serverRoom);
    final clientOpId = op['client_op_id'] as String;
    await _local.deleteOperation(clientOpId);
    debugPrint(
      '[RoomsRepository] Conflicto en room ${serverRoom.id}: se descartó '
      'la edición local, gana la versión del servidor '
      '(updated_at=${serverRoom.updatedAt}).',
    );
  }

  // ===== Cierre de sesión =====

  Future<void> clearLocalData() => _local.clearAll();
}
