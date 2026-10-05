import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/rooms_repository.dart';
import '../models/room.dart';
import '../models/user_location.dart';
import '../services/connectivity_service.dart';

/// Estado global de la lista de salas — offline-first (taller Semana 12).
///
/// Taller Semana 13 (Bloque 6): este provider ya no habla con HTTP ni
/// con SQLite directamente. Toda esa lógica (dónde vive la caché, cómo
/// se arma la cola de operaciones pendientes, cómo se reintenta la
/// sincronización) vive en `RoomsRepository`; este provider solo guarda
/// el estado de UI (`rooms`, `isLoading`, `isOffline`, etc.) y notifica a
/// los widgets. No sabe, ni le importa, de dónde vino cada `Room`.
class RoomsProvider extends ChangeNotifier {
  RoomsProvider({RoomsRepository? repository, ConnectivityService? connectivity})
      : _repository = repository ?? RoomsRepository(),
        _connectivity = connectivity ?? ConnectivityService();

  final RoomsRepository _repository;
  final ConnectivityService _connectivity;

  bool _isReconnecting = false;
  bool _reconnectLoopActive = false;
  bool _showSyncedNotice = false;
  Timer? _noticeTimer;

  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isOffline = false;
  DateTime? _lastSyncedAt;
  int _pendingCount = 0;
  String? _lastSyncError;
  bool _isLoadingMore = false;

  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;

  /// `true` mientras la app, ya con red, intenta sincronizar la cola y
  /// refrescar la lista tras haber estado sin conexión (ej. al quitar el
  /// modo avión). La UI muestra "Reconectando..." en vez de un error.
  bool get isReconnecting => _isReconnecting;

  /// `true` unos segundos después de que la cola pendiente se sincronizó
  /// por completo: la UI muestra "Todo sincronizado".
  bool get showSyncedNotice => _showSyncedNotice;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  int get pendingCount => _pendingCount;

  /// Fase 1 (Plan de fases pendientes): `true` mientras se pide la
  /// página siguiente con [loadMore]; la UI la usa para mostrar un
  /// loader en el botón "Cargar más" en vez de bloquear toda la
  /// pantalla.
  bool get isLoadingMore => _isLoadingMore;

  /// `true` si el backend reportó que hay más salas que las ya
  /// cargadas (hay página siguiente).
  bool get hasMore => _repository.hasMoreRooms;

  /// Mensaje del backend (ej. 422) para la última operación de creación
  /// o edición que se rechazó al sincronizar. La UI lo lee una sola vez
  /// (vía [consumeLastSyncError]) para mostrarlo (ej. en un SnackBar) y
  /// no repetirlo en cada rebuild.
  String? get lastSyncError => _lastSyncError;

  /// Devuelve el último error de sincronización y lo limpia, para que
  /// no se vuelva a mostrar si el widget se reconstruye.
  String? consumeLastSyncError() {
    final error = _lastSyncError;
    _lastSyncError = null;
    return error;
  }

  /// `GET /rooms/list` con caída a caché. Se llama al entrar a la
  /// pantalla y en el pull-to-refresh.
  ///
  /// Con [silent] no se muestra el loader ni se publica ningún error de
  /// red (se usa en los reintentos automáticos al reconectar).
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    final outcome = await _repository.refresh();
    await _reloadFromRepository();

    if (outcome.serverUnreachable) {
      // Hay red pero el servidor no respondió (típico justo al quitar el
      // modo avión, antes de que el wifi termine de conectar). Si hay
      // datos en caché se sigue en modo local y se reintenta solo; el
      // error a pantalla completa solo aparece si NO hay nada que mostrar.
      _isOffline = true;
      _errorMessage = (_rooms.isEmpty && !silent) ? outcome.errorMessage : null;
    } else {
      _isOffline = outcome.isOffline;
      _errorMessage = outcome.errorMessage;
    }

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

  /// Fase 1 (Plan de fases pendientes): pide la página siguiente de
  /// salas y la agrega al final de [rooms] (no reemplaza lo ya
  /// mostrado). No hace nada si ya se está cargando o si el backend ya
  /// dijo que no hay más páginas ([hasMore] en `false`).
  Future<void> loadMore() async {
    if (_isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    final outcome = await _repository.loadMoreRooms();
    if (outcome.errorMessage != null) _lastSyncError = outcome.errorMessage;

    await _reloadFromRepository();

    _isLoadingMore = false;
    notifyListeners();
  }

  /// Taller Semana 14 (Fase 4): registra la ubicación aproximada del
  /// usuario (o `null` = "sin ubicación", si el permiso no está
  /// concedido). Se guarda en la caché local y, si la ubicación
  /// enviable cambió, se refresca la lista para que el backend reciba la
  /// nueva ubicación (`GET /rooms/list?lat=..&lng=..`).
  ///
  /// Es "best effort": un fallo al guardar no debe romper la pantalla.
  Future<void> updateLocation(UserLocation? location) async {
    try {
      final changed = await _repository.saveLocation(location);
      if (changed) await refresh();
    } catch (e) {
      debugPrint('[RoomsProvider] No se pudo guardar la ubicación: $e');
    }
  }

  /// Procesa la cola pendiente si hay conexión. Se llama tras
  /// crear/editar, tras un `refresh()` exitoso, y desde `app.dart` al
  /// detectar reconexión.
  Future<void> trySyncPending() async {
    await _runSync();
  }

  Future<RoomsSyncOutcome> _runSync() async {
    try {
      final outcome = await _repository.trySyncPending();
      if (outcome.errorMessage != null) {
        _lastSyncError = outcome.errorMessage;
      }
      if (outcome.syncedAny) {
        await _reloadFromRepository();
      }
      if (outcome.networkFailed && !_isOffline) {
        // Quedaron cambios en la cola por falta de red: se refleja en el
        // aviso de la pantalla (modo local, pendientes de sincronizar).
        _isOffline = true;
        notifyListeners();
      } else if (outcome.syncedAny || outcome.errorMessage != null) {
        // Si el servidor respondió, hay conexión: se sale de "modo local"
        // sin esperar al próximo refresh (antes el aviso se quedaba
        // pegado aunque los cambios ya se hubieran sincronizado).
        if (outcome.syncedAny && !outcome.networkFailed) _isOffline = false;
        notifyListeners();
      }
      if (outcome.syncedAny && _pendingCount == 0 && !outcome.networkFailed) {
        _flashSyncedNotice();
      }
      return outcome;
    } catch (_) {
      // La sincronización es best-effort; un fallo acá no debe romper
      // la UI. La cola queda intacta para el próximo intento.
      return const RoomsSyncOutcome();
    }
  }

  void _flashSyncedNotice() {
    _showSyncedNotice = true;
    notifyListeners();
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      _showSyncedNotice = false;
      notifyListeners();
    });
  }

  /// El dispositivo perdió la conexión (ej. modo avión): se pasa a modo
  /// local al instante, sin esperar a que falle una petición.
  void markOffline() {
    if (_isOffline) return;
    _isOffline = true;
    notifyListeners();
  }

  /// Se llama cuando el dispositivo recupera red (ej. al quitar el modo
  /// avión) y también periódicamente mientras haya cambios pendientes.
  ///
  /// La señal de "hay conexión" suele llegar ANTES de que el wifi esté
  /// realmente usable, así que un único intento falla con "no se pudo
  /// conectar con el servidor". Por eso aquí se reintenta con espera
  /// creciente (2, 4, 6, 8 s...) hasta lograr sincronizar la cola y
  /// refrescar la lista, SIN mostrar errores al usuario mientras tanto:
  /// solo el aviso "Reconectando...".
  Future<void> syncAfterReconnect() async {
    if (_reconnectLoopActive) return;
    _reconnectLoopActive = true;

    try {
      // Los sockets abiertos antes del corte (modo avión / cambio de red)
      // quedan muertos: se descartan para que los intentos usen
      // conexiones nuevas.
      _repository.resetNetwork();

      // Las operaciones que se dieron por vencidas mientras no había red
      // vuelven a la cola: con conexión se reintentan.
      await _repository.reviveFailedOperations();
      await _reloadFromRepository();
      notifyListeners();

      const maxAttempts = 8;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        if (!await _connectivity.isOnline()) {
          // Volvió a quedar sin red: se espera la próxima señal.
          markOffline();
          break;
        }

        _isReconnecting = true;
        notifyListeners();

        final outcome = await _runSync();
        if (!outcome.networkFailed) {
          await refresh(silent: true); // también reintenta la cola si hay red
          if (!_isOffline && _pendingCount == 0) break;
        }

        // Entre intentos la UI deja de mostrar el spinner (queda el aviso
        // de "modo local, reintentando") para no parecer colgada.
        _isReconnecting = false;
        notifyListeners();

        final seconds = math.min(2 + attempt * 2, 8);
        await Future<void>.delayed(Duration(seconds: seconds));
        if (attempt >= 1) _repository.resetNetwork();
      }
    } finally {
      _isReconnecting = false;
      _reconnectLoopActive = false;
      notifyListeners();
    }
  }

  /// Red de seguridad periódica (la dispara `app.dart`): si hay cambios
  /// pendientes o seguimos en modo local pero el dispositivo ya tiene red,
  /// reintenta la sincronización aunque no haya llegado ninguna señal.
  Future<void> retryIfNeeded() async {
    if (_reconnectLoopActive || _isLoading) return;
    if (_pendingCount == 0 && !_isOffline) return;
    if (!await _connectivity.isOnline()) return;
    await syncAfterReconnect();
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
    _showSyncedNotice = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }
}
