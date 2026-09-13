import 'api_client.dart';

/// Constantes globales de la app.
///
/// Taller Semana 13 (Bloque 2): la resolución de la URL base por
/// ambiente vive ahora en `ApiClient.resolveBaseUrl()` (junto con el
/// timeout explícito y la instancia única de `http.Client`). Este
/// getter se mantiene solo por compatibilidad con código existente que
/// ya lo referenciaba.
class AppConstants {
  AppConstants._();

  static String get apiBaseUrl => ApiClient.resolveBaseUrl();
}
