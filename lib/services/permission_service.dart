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
class PermissionService {
  /// Estado actual del permiso de micrófono, sin solicitarlo.
  Future<AppPermissionStatus> checkMicrophone() =>
      _map(Permission.microphone.status);

  /// Solicita el permiso de micrófono si hace falta y devuelve el
  /// estado resultante. Si ya estaba concedido, no muestra ningún
  /// diálogo del sistema.
  Future<AppPermissionStatus> requestMicrophone() =>
      _map(Permission.microphone.request());

  /// Estado actual del permiso de ubicación, sin solicitarlo.
  Future<AppPermissionStatus> checkLocation() =>
      _map(Permission.locationWhenInUse.status);

  /// Solicita el permiso de ubicación si hace falta y devuelve el
  /// estado resultante.
  Future<AppPermissionStatus> requestLocation() =>
      _map(Permission.locationWhenInUse.request());

  /// Abre la pantalla de ajustes de la app (para conceder un permiso
  /// que fue denegado permanentemente). Devuelve `false` si el sistema
  /// no pudo abrir Ajustes.
  Future<bool> openSettings() => openAppSettings();

  Future<AppPermissionStatus> _map(Future<PermissionStatus> status) async {
    final result = await status;
    switch (result) {
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
