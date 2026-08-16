import 'api_service.dart';

/// Servicio de autenticación contra el backend Flask.
///
/// Stub de la Fase 1. Se completa en la Fase 2 con `register`, `login`
/// y `me`, consumiendo `POST /auth/register`, `POST /auth/login` y
/// `GET /auth/me`.
class AuthService {
  AuthService(this._apiService);

  final ApiService _apiService;
}
