import 'package:flutter/foundation.dart';

import '../models/room.dart';
import '../services/api_service.dart';
import '../services/rooms_service.dart';

/// Estado global de la lista de salas.
///
/// `rooms_list_screen.dart` llama a `refresh()` al entrar y en el
/// pull-to-refresh, y a `create(name)` desde el diálogo de creación.
class RoomsProvider extends ChangeNotifier {
  RoomsProvider({RoomsService? roomsService})
      : _roomsService = roomsService ?? RoomsService(ApiService());

  final RoomsService _roomsService;

  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// `GET /rooms/list`.
  Future<void> refresh() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _rooms = await _roomsService.listRooms();
    } on UnauthorizedException {
      // El logout y la navegación a /login ya se disparan de forma
      // centralizada en ApiService.onUnauthorized; no hace falta mostrar
      // un error acá.
    } on RoomException catch (e) {
      _errorMessage = e.message;
    } on NetworkException catch (e) {
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Ocurrió un error inesperado';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// `POST /rooms`. Relanza la excepción para que la pantalla la
  /// muestre; si tiene éxito, refresca la lista.
  Future<void> create(String name) async {
    await _roomsService.createRoom(name);
    await refresh();
  }
}
