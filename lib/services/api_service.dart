import '../core/constants.dart';

/// Excepción lanzada cuando el backend responde 401.
///
/// Se maneja de forma centralizada en la Fase 5 (logout automático).
class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message = 'No autorizado']);
  final String message;

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Único punto de configuración de la URL base del backend.
///
/// Ninguna pantalla debe hacer `http.get`/`http.post` directo: todo pasa
/// por aquí (o por los servicios que lo envuelven, como `auth_service.dart`
/// y `rooms_service.dart`).
///
/// Stub de la Fase 1. Los métodos `authorizedGet`/`authorizedPost` se
/// implementan en la Fase 2.
class ApiService {
  ApiService({this.baseUrl = AppConstants.apiBaseUrl});

  final String baseUrl;

  Uri buildUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }
}
