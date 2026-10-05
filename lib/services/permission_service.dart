import 'package:permission_handler/permission_handler.dart';

/// Los 4 estados relevantes de un permiso del sistema (Taller Semana 14).
///
/// `permission_handler` expone más granularidad (`limited`, `provisional`,
/// etc.), pero para la UI de esta app solo importan estos cuatro: se
/// colapsan los casos intermedios de iOS (`limited`, `provisional`) en
/// [granted], porque implican que la funcionalidad puede usarse.
enum AppPermissionStatus {
  /// El permiso está concedido; se puede usar la funcionalidad.
  granted,

  /// El permiso fue denegado, pero se puede volver a pedir (mostrando de
  /// nuevo la explicación).
  denied,

  /// El usuario denegó permanentemente ("no volver a preguntar" en
  /// Android, o rechazó dos veces en iOS). Pedir el permiso de nuevo no
  /// muestra el diálogo del sistema: hay que mandar al usuario a
  /// Ajustes.
  permanentlyDenied,

  /// El permiso no está disponible para esta app/dispositivo (ej.
  /// restricciones parentales, política del dispositivo). No hay nada
  /// que la app pueda hacer salvo informar.
  restricted,
}

/// Wrapper delgado sobre `permission_handler`.
///
/// Punto único de verdad para el estado de permisos de la app: tanto
/// `RecorderService` (micrófono) como `LocationService` (ubicación) lo
/// usan, en vez de que cada uno implemente su propia lógica de los 4
/// estados. Esto evita, por ejemplo, que un permiso se trate como
/// "denegado" en una pantalla y como "denegado permanentemente" en
/// otra.
///
/// ### Regla de las dos solicitudes
/// El diálogo del sistema se muestra como máximo [maxSystemPrompts]
/// veces (2). Si el usuario lo deniega las dos veces, el permiso pasa a
/// [AppPermissionStatus.permanentlyDenied] y la tercera acción de la UI
/// lleva a los Ajustes del teléfono. Se cuenta aquí (y no solo se
/// confía en el sistema) para que el comportamiento sea el mismo en
/// todos los dispositivos y versiones de Android.
class PermissionService {
  /// Veces que se muestra el diálogo del sistema antes de mandar al
  /// usuario a Ajustes.
  static const int maxSystemPrompts = 2;

  /// Denegaciones por permiso (clave: `Permission.value`). Es `static`
  /// porque cada pantalla crea su propia instancia de
  /// [PermissionService] y el conteo debe compartirse entre ellas.
  static final Map<int, int> _denials = <int, int>{};

  /// Estado actual del permiso de micrófono, sin solicitarlo.
  Future<AppPermissionStatus> checkMicrophone() =>
      _check(Permission.microphone);

  /// Solicita el permiso de micrófono si hace falta y devuelve el
  /// estado resultante. Si ya estaba concedido, o ya se agotaron las
  /// solicitudes, no muestra ningún diálogo del sistema.
  Future<AppPermissionStatus> requestMicrophone() =>
      _request(Permission.microphone);

  /// Estado actual del permiso de ubicación, sin solicitarlo.
  Future<AppPermissionStatus> checkLocation() =>
      _check(Permission.locationWhenInUse);

  /// Solicita el permiso de ubicación si hace falta y devuelve el
  /// estado resultante (misma regla de dos solicitudes).
  Future<AppPermissionStatus> requestLocation() =>
      _request(Permission.locationWhenInUse);

  /// Abre la pantalla de ajustes de la app (para conceder un permiso
  /// que fue denegado permanentemente). Devuelve `false` si el sistema
  /// no pudo abrir Ajustes.
  ///
  /// Reinicia el conteo de denegaciones: el usuario va a decidir en
  /// Ajustes y, al volver, se re-evalúa el estado real del permiso.
  Future<bool> openSettings() {
    _denials.clear();
    return openAppSettings();
  }

  Future<AppPermissionStatus> _check(Permission permission) async {
    final status = _map(await permission.status);
    return _applyDenialLimit(permission, status);
  }

  Future<AppPermissionStatus> _request(Permission permission) async {
    // Solo se muestra el diálogo si el permiso sigue "denegado pero
    // pidible": concedido, restringido o ya agotado no lo muestran.
    final current = await _check(permission);
    if (current != AppPermissionStatus.denied) return current;

    final result = _map(await permission.request());
    if (result == AppPermissionStatus.denied) {
      _denials[permission.value] = (_denials[permission.value] ?? 0) + 1;
    }
    return _applyDenialLimit(permission, result);
  }

  /// Concedido limpia el conteo; "denegado" con las solicitudes
  /// agotadas se eleva a "denegado permanentemente".
  AppPermissionStatus _applyDenialLimit(
    Permission permission,
    AppPermissionStatus status,
  ) {
    if (status == AppPermissionStatus.granted) {
      _denials.remove(permission.value);
      return status;
    }
    final denials = _denials[permission.value] ?? 0;
    if (status == AppPermissionStatus.denied && denials >= maxSystemPrompts) {
      return AppPermissionStatus.permanentlyDenied;
    }
    return status;
  }

  AppPermissionStatus _map(PermissionStatus status) {
    switch (status) {
      case PermissionStatus.granted:
      case PermissionStatus.limited:
      case PermissionStatus.provisional:
        return AppPermissionStatus.granted;
      case PermissionStatus.denied:
        return AppPermissionStatus.denied;
      case PermissionStatus.permanentlyDenied:
        return AppPermissionStatus.permanentlyDenied;
      case PermissionStatus.restricted:
        return AppPermissionStatus.restricted;
    }
  }
}
