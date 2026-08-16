import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Estado global de autenticación.
///
/// `app.dart` decide qué pantalla mostrar en función de
/// `isAuthenticated`; las pantallas de login/registro llaman a
/// `login()`/`register()` y navegan según el resultado.
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService}) : _authService = authService ?? AuthService();

  final AuthService _authService;

  User? _currentUser;
  bool _isLoading = false;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;

  /// Se llama al arrancar la app: si hay un token guardado, intenta
  /// `GET /auth/me`. Si responde 200, deja al usuario autenticado; si
  /// responde 401 (u otro error), el token se descarta.
  Future<void> tryRestoreSession() async {
    _isLoading = true;
    notifyListeners();
    try {
      _currentUser = await _authService.me();
    } on UnauthorizedException {
      await _authService.logout();
      _currentUser = null;
    } catch (_) {
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Lanza `AuthException` si las credenciales son inválidas, para que
  /// la pantalla de login muestre el mensaje.
  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.login(email, password);
      _currentUser = await _authService.me();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Lanza `AuthException` si el registro falla (ej. email ya usado).
  Future<void> register(String username, String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.register(username, email, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    _currentUser = null;
    notifyListeners();
  }
}
