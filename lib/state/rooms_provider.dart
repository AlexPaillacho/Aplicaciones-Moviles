import 'package:flutter/foundation.dart';

import '../data/rooms_repository.dart';
import '../models/room.dart';

/// Estado global de la lista de salas — offline-first (taller Semana 12).
///
/// Taller Semana 13 (Bloque 6): este provider ya no habla con HTTP ni
/// con SQLite directamente. Toda esa lógica (dónde vive la caché, cómo
/// se arma la cola de operaciones pendientes, cómo se reintenta la
/// sincronización) vive en `RoomsRepository`; este provider solo guarda
/// el estado de UI (`rooms`, `isLoading`, `isOffline`, etc.) y notifica a
/// los widgets. No sabe, ni le importa, de dónde vino cada `Room`.
class RoomsProvider extends ChangeNotifier {
  RoomsProvider({RoomsRepository? repository}) : _repository = repository ?? RoomsRepository();

  final RoomsRepository _repository;

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

    final outcome = await _repository.refresh();
    _isOffline = outcome.isOffline;
    _errorMessage = outcome.errorMessage;

    await _reloadFromRepository();

    _isLoading = false;
    notifyListeners();

    // Aprovechamos que acabamos de confirmar conexión (o no) para
    // intentar vaciar la cola pendiente.
    if (!_isOffline) {
      await trySyncPending();
    }
  }

  /// Crea una sala. Se aplica de inmediato en la caché local (optimista,
  /// vía `RoomsRepository`) y se intenta sincronizar enseguida si hay
  /// conexión.
  Future<void> create(String name, {int? hostId, String? hostUsername}) async {
    await _repository.createOptimistic(name, hostId: hostId, hostUsername: hostUsername);

    await _reloadFromRepository();
    notifyListeners();

    await trySyncPending();
  }

  /// Edita una sala. `room` debe ser la instancia tal como está en
  /// `rooms` ahora mismo: su `updatedAt` es la base con la que el
  /// servidor detectará (o no) un conflicto al sincronizar.
  Future<void> update(Room room, {String? name, bool? active}) async {
    await _repository.updateOptimistic(room, name: name, active: active);

    await _reloadFromRepository();
    notifyListeners();

    await trySyncPending();
  }

  /// Procesa la cola pendiente si hay conexión. Se llama tras
  /// crear/editar, tras un `refresh()` exitoso, y desde `app.dart` al
  /// detectar reconexión.
  Future<void> trySyncPending() async {
    try {
      final syncedSomething = await _repository.trySyncPending();
      if (syncedSomething) {
        await _reloadFromRepository();
        notifyListeners();
      }
    } catch (_) {
      // La sincronización es best-effort; un fallo acá no debe romper
      // la UI. La cola queda intacta para el próximo intento.
    }
  }

  Future<void> _reloadFromRepository() async {
    _rooms = await _repository.getCachedRooms();
    _lastSyncedAt = await _repository.getLastSyncedAt();
    _pendingCount = await _repository.getPendingCount();
  }

  /// Se llama desde el logout: borra toda la caché y la cola pendiente
  /// (el taller exige no dejar datos de la sesión en el dispositivo).
  Future<void> clearLocalData() async {
    await _repository.clearLocalData();
    _rooms = [];
    _lastSyncedAt = null;
    _pendingCount = 0;
    _isOffline = false;
    notifyListeners();
  }
}
