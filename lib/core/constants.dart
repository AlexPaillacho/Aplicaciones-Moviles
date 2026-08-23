import 'package:flutter/foundation.dart' show kIsWeb;

/// Constantes globales de la app.
///
/// La URL base del backend se puede seguir inyectando en tiempo de
/// compilación con `--dart-define=API_BASE_URL=...` si lo necesitas
/// (por ejemplo, para apuntar a un servidor remoto).
///
/// Si NO se define, la app elige un valor por defecto según la
/// plataforma en la que corre:
///   - Web (Chrome/Edge): `http://localhost:5000`
///   - Android emulator: `http://10.0.2.2:5000` (así el emulador
///     llega al `localhost` de la máquina host).
class AppConstants {
  AppConstants._();

  static const String _envApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:5000';
    }
    return 'http://10.0.2.2:5000';
  }
}
