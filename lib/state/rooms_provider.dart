import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/room.dart';
import '../services/api_service.dart';
import '../services/local_db_service.dart';
import '../services/rooms_service.dart';
import '../services/sync_service.dart';

/// Estado global de la lista de salas — offline-first (taller Semana 12).
///
/// Todas las lecturas de UI (`rooms`) vienen de la caché local
/// (`LocalDbService`); `refresh()` intenta actualizarla contra el
/// backend, pero si no hay conexión simplemente deja lo que ya había en
/// caché y prende [isOffline]. Las escrituras (`create`/`update`) se
/// aplican primero de forma optimista en la caché y se encolan; se
/// intentan sincronizar de inmediato si hay conexión, y si no, quedan
/// para la próxima reconexión (`SyncService`, disparado desde
/// `app.dart`).
class RoomsProvider extends ChangeNotifier {
  RoomsProvider({
    RoomsService? roomsService,
    LocalDbService? localDb,
    SyncService? syncService,
  })  : _roomsService = roomsService ?? RoomsService(ApiService()),
        _localDb = localDb ?? LocalDbService.instance,
        _syncService = syncService ?? SyncService();

  final RoomsService _roomsService;
  final LocalDbService _localDb;
  final SyncService _syncService;
  final _uuid = const Uuid();

  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOffline = false;
  DateTime? _lastSyncedAt;
  int _pendingCount = 0;

  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get pendingCount => _pendingCount;

  /// `GET /rooms/list` con caída a caché. Se llama al entrar a la
  /// pantalla y en el pull-to-refresh.
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final serverRooms = await _roomsService.listRooms();
      await _localDb.upsertServerRooms(serverRooms);
      await _localDb.setLastSyncedAt(DateTime.now());
      _isOffline = false;
    } on UnauthorizedException {
      // Logout y navegación ya ocurren de forma centralizada en
      // ApiService.onUnauthorized.
    } on NetworkException {
      // Sin conexión: la UI sigue mostrando la caché de más abajo, con
      // el indicador de "actualizado hace X" y el aviso de modo offline.
      _isOffline = true;
    } on RoomException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Ocurrió un error inesperado';
    }

    await _reloadFromCache();

    _isLoading = false;
    notifyListeners();

    // Aprovechamos que acabamos de confirmar conexión (o no) para
    // intentar vaciar la cola pendiente.
    if (!_isOffline) {
      await trySyncPending();
    }
  }

  /// Crea una sala. Se aplica de inmediato en la caché local con un id
  /// temporal negativo (para que aparezca en la lista al toque) y se
  /// encola; `hostId`/`hostUsername` son los del usuario actual, para
  /// que la card muestre el host correcto mientras la sala todavía no
  /// tiene id real del servidor.
  Future<void> create(String name, {int? hostId, String? hostUsername}) async {
    final tempId = -DateTime.now().microsecondsSinceEpoch;
    final optimisticRoom = Room(
      id: tempId,
      name: name,
      active: true,
      hostId: hostId,
      hostUsername: hostUsername,
      updatedAt: DateTime.now(),
    );

    await _localDb.upsertRoom(optimisticRoom);
    await _localDb.enqueueCreate(
      clientOpId: _uuid.v4(),
      localTempId: tempId,
      name: name,
    );

    await _reloadFromCache();
    notifyListeners();

    await trySyncPending();
  }

  /// Edita una sala. `room` debe ser la instancia tal como está en
  /// `rooms` ahora mismo: su `updatedAt` es la base con la que el
  /// servidor detectará (o no) un conflicto al sincronizar.
  Future<void> update(Room room, {String? name, bool? active}) async {
    final optimisticRoom = room.copyWith(
      name: name,
      active: active,
      updatedAt: DateTime.now(),
    );

    await _localDb.upsertRoom(optimisticRoom);
    await _localDb.enqueueUpdate(
      clientOpId: _uuid.v4(),
      roomId: room.id,
      name: name,
      active: active,
      baseUpdatedAt: room.updatedAt.toIso8601String(),
    );

    await _reloadFromCache();
    notifyListeners();

    await trySyncPending();
  }

  /// Procesa la cola pendiente si hay conexión. Se llama tras
  /// crear/editar, tras un `refresh()` exitoso, y desde `app.dart` al
  /// detectar reconexión.
  Future<void> trySyncPending() async {
    try {
      final syncedSomething = await _syncService.processPendingQueue();
      if (syncedSomething) {
        await _reloadFromCache();
        notifyListeners();
      }
    } catch (_) {
      // La sincronización es best-effort; un fallo acá no debe romper
      // la UI. La cola queda intacta para el próximo intento.
    }
  }

  Future<void> _reloadFromCache() async {
    _rooms = await _localDb.getCachedRooms();
    _lastSyncedAt = await _localDb.getLastSyncedAt();
    _pendingCount = await _localDb.countPending();
  }

  /// Se llama desde el logout: borra toda la caché y la cola pendiente
  /// (el taller exige no dejar datos de la sesión en el dispositivo).
  Future<void> clearLocalData() async {
    await _localDb.clearAll();
    _rooms = [];
    _lastSyncedAt = null;
    _pendingCount = 0;
    _isOffline = false;
    notifyListeners();
  }
}
