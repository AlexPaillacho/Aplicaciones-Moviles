import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'permission_service.dart';

/// Se lanza cuando el permiso de ubicación no está concedido.
///
/// Se separa de [LocationServiceDisabledException] a propósito: son dos
/// condiciones distintas (permiso de la app vs. GPS del sistema
/// apagado), como advierte la guía del taller, y la UI debe reaccionar
/// distinto a cada una (Fase 3).
class LocationPermissionException implements Exception {
  const LocationPermissionException(this.status);

  /// Estado del permiso al momento de la solicitud. Nunca es
  /// [AppPermissionStatus.granted] cuando se lanza esta excepción.
  final AppPermissionStatus status;

  @override
  String toString() => 'Permiso de ubicación no concedido: $status';
}

/// Se lanza cuando el permiso está concedido pero el servicio de
/// ubicación del dispositivo (GPS) está apagado.
class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();

  @override
  String toString() => 'El servicio de ubicación del dispositivo está apagado';
}

/// Envuelve `geolocator` para sugerir salas de práctica cercanas
/// (Taller Semana 14, capacidad opcional). No conoce la UI ni el
/// backend: solo expone `getCurrentPosition()` y deja que quien la
/// llame decida qué hacer con cada excepción.
class LocationService {
  LocationService({PermissionService? permissionService})
      : _permissionService = permissionService ?? PermissionService();

  final PermissionService _permissionService;

  /// Verifica permiso y servicio de ubicación, y devuelve la posición
  /// actual con precisión aproximada (suficiente para "salas cercanas";
  /// no se pide precisión alta a propósito, ver `fase0_seleccion...`).
  ///
  /// Lanza [LocationPermissionException] si el permiso no está
  /// concedido, o [LocationServiceDisabledException] si el GPS del
  /// sistema está apagado. Si no se obtiene posición (2 intentos de 8 s) lanza
  /// `TimeoutException`.
  Future<Position> getCurrentPosition() async {
    var status = await _permissionService.checkLocation();
    if (status == AppPermissionStatus.denied) {
      status = await _permissionService.requestLocation();
    }
    if (status != AppPermissionStatus.granted) {
      throw LocationPermissionException(status);
    }

    // Se comprueba el servicio del sistema aparte del permiso: se puede
    // tener el permiso concedido y aun así no poder ubicar al usuario
    // porque el GPS está apagado. Va DESPUÉS del permiso (Fase 3) para
    // que `LocationServiceDisabledException` signifique siempre "permiso
    // concedido pero GPS apagado", y la UI pueda decirlo sin mentir.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    // Rapidez: para "salas cercanas" basta una posición aproximada, así
    // que primero se usa la ÚLTIMA posición conocida del sistema (llega al
    // instante). Esperar siempre un fix nuevo en modo "low" era lo que
    // hacía que a veces tardara varios intentos en cargar.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
    } catch (_) {
      // No disponible en esta plataforma/dispositivo: se pide un fix nuevo.
    }

    // Sin posición previa: fix nuevo con dos intentos cortos (el primero
    // suele "despertar" al proveedor de ubicación y el segundo ya
    // responde) en vez de uno largo que termina en "intenta nuevamente".
    // Sin timeLimit la llamada podría esperar indefinidamente (ej. en
    // interiores); al vencer ambos lanza `TimeoutException`, que la
    // pantalla trata como un error reintentable.
    const attempts = 2;
    for (var i = 1; i <= attempts; i++) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } on TimeoutException {
        if (i == attempts) rethrow;
      }
    }
    throw TimeoutException('No se obtuvo la posición');
  }

  /// Atajo para la UI: solo dice si vale la pena mostrar la sección de
  /// "salas cercanas", sin exponer la posición ni lanzar excepciones.
  Future<bool> get isAvailable async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    final status = await _permissionService.checkLocation();
    return status == AppPermissionStatus.granted;
  }

  /// Abre los ajustes de ubicación del SISTEMA (para encender el GPS
  /// cuando lanza [LocationServiceDisabledException]). No es lo mismo
  /// que `PermissionService.openSettings()`, que abre los ajustes de
  /// PERMISOS de la app. Devuelve `false` si el sistema no pudo abrirlos.
  ///
  /// Fase 3 (Taller Semana 14): vive acá y no en la pantalla para que la
  /// UI no tenga que importar `geolocator`, que define su propia
  /// `LocationServiceDisabledException` y chocaría con la de este
  /// archivo.
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
