import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Ambientes soportados. Se selecciona con `--dart-define=ENV=prod`
/// (por defecto `dev`).
enum AppEnvironment { dev, prod }

/// Único punto de configuración del cliente HTTP de toda la app
/// (Taller Semana 13, Bloque 2).
///
/// Nota de diseño (para el documento del taller): se mantiene
/// `package:http` en vez de migrar a un paquete de terceros nuevo como
/// Dio. Ya está integrado en toda la app y cubierto por los tests
/// existentes (`http/testing.dart`), y el comportamiento de
/// "interceptores" que pide el taller (Bloques 3 y 4) no depende de que
/// la librería HTTP lo ofrezca nativo: se implementa como funciones
/// explícitas dentro de `ApiService`, ejecutadas antes/después de cada
/// petición.
///
/// Esta clase resuelve:
/// - Una única instancia de `http.Client` para toda la app.
/// - La URL base por ambiente (dev/prod), vía `--dart-define`.
/// - Un timeout explícito único para todas las peticiones (antes no
///   existía ninguno: una petición colgada nunca terminaba, pese a que
///   `ApiService` ya intentaba capturar `TimeoutException`).
class ApiClient {
  ApiClient._internal();

  static final ApiClient _instance = ApiClient._internal();

  /// Única instancia del cliente HTTP para toda la app.
  factory ApiClient() => _instance;

  /// Instancia única de `http.Client`. Todo el tráfico HTTP de
  /// producción pasa por acá (los tests siguen pudiendo inyectar su
  /// propio `MockClient` a través de `ApiService(client: ...)`).
  http.Client _httpClient = http.Client();

  http.Client get httpClient => _httpClient;

  /// Cierra el cliente y crea uno nuevo, descartando las conexiones
  /// persistentes del pool. Se usa al recuperar la red (ej. al quitar el
  /// modo avión): los sockets abiertos ANTES del corte quedan muertos y
  /// pueden seguir fallando con "no se pudo conectar" aunque el wifi ya
  /// esté activo.
  void resetConnections() {
    final old = _httpClient;
    _httpClient = http.Client();
    old.close();
  }

  /// Timeout explícito aplicado a cada petición (Bloque 2).
  static const Duration requestTimeout = Duration(seconds: 15);

  static const String _envApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  static const String _envName = String.fromEnvironment(
    'ENV',
    defaultValue: 'dev',
  );

  static AppEnvironment get environment =>
      _envName == 'prod' ? AppEnvironment.prod : AppEnvironment.dev;

  static bool get isProduction => environment == AppEnvironment.prod;

  /// Resuelve la URL base según el ambiente.
  ///
  /// - Producción (`ENV=prod`): exige `API_BASE_URL` explícito y con
  ///   esquema `https://` (Bloque 8 exige HTTPS en producción). Si falta
  ///   o no es `https`, falla rápido en vez de arrancar mal configurada.
  /// - Desarrollo: usa `API_BASE_URL` si se definió, o el valor por
  ///   defecto según la plataforma (emulador Android vs Web/desktop).
  static String resolveBaseUrl() {
    if (isProduction) {
      if (_envApiBaseUrl.isEmpty) {
        throw StateError(
          'Falta --dart-define=API_BASE_URL=https://... para el build '
          'de producción (ENV=prod).',
        );
      }
      if (!_envApiBaseUrl.startsWith('https://')) {
        throw StateError(
          'En producción (ENV=prod) API_BASE_URL debe usar https. '
          'Valor recibido: $_envApiBaseUrl',
        );
      }
      return _envApiBaseUrl;
    }

    if (_envApiBaseUrl.isNotEmpty) {
      return _envApiBaseUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:5000';
    }
    return 'http://192.168.101.24:5000'; // IP de la PC de desarrollo en la red Wi-Fi local
  }
}
