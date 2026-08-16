/// Constantes globales de la app.
///
/// La URL base del backend se inyecta en tiempo de compilación con
/// `--dart-define=API_BASE_URL=...` (ver Fase 0 del plan de desarrollo).
/// Si no se define, cae a `10.0.2.2:5000`, que es la dirección que usa
/// el emulador de Android para llegar a `localhost` de la máquina host.
class AppConstants {
  AppConstants._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );
}
