/// Ubicación APROXIMADA del usuario (Taller Semana 14, Fase 4).
///
/// Es lo que se guarda en la caché local (`last_location`) y lo que se
/// envía al backend al listar/crear salas. Nunca contiene coordenadas
/// exactas: se construye con [UserLocation.approximate], que las
/// redondea a [precisionDecimals] decimales.
///
/// ### Por qué se redondea
/// Se declaró solo `ACCESS_COARSE_LOCATION` y se pide precisión baja,
/// porque para "salas cercanas" no hace falta más (criterio de
/// cumplimiento de la Fase 0: no pedir más acceso del necesario). El
/// redondeo aplica el mismo criterio a lo que se almacena y se
/// transmite: 2 decimales equivalen a ~1,1 km, suficiente para ordenar
/// salas por cercanía a escala de ciudad sin guardar dónde está el
/// usuario con más detalle del necesario.
///
/// Para cambiar la precisión basta modificar [precisionDecimals]: es el
/// único punto donde se decide.
class UserLocation {
  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  /// Decimales conservados al redondear (2 ≈ 1,1 km).
  static const int precisionDecimals = 2;

  /// Construye una ubicación redondeando las coordenadas recibidas del
  /// GPS. Usar SIEMPRE este constructor con datos del dispositivo.
  factory UserLocation.approximate({
    required double latitude,
    required double longitude,
    DateTime? capturedAt,
  }) {
    return UserLocation(
      latitude: _round(latitude),
      longitude: _round(longitude),
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }

  final double latitude;
  final double longitude;

  /// Cuándo se obtuvo esta posición.
  final DateTime capturedAt;

  /// true si ambas ubicaciones caen en las mismas coordenadas (ya
  /// redondeadas). Sirve para no refrescar la lista si el usuario no se
  /// movió lo suficiente como para cambiar de "cuadrícula".
  bool hasSameCoordinatesAs(UserLocation other) =>
      latitude == other.latitude && longitude == other.longitude;

  static double _round(double value) =>
      double.parse(value.toStringAsFixed(precisionDecimals));

  @override
  String toString() => 'UserLocation($latitude, $longitude)';
}

/// Lo último que se sabe de la ubicación del usuario, tal como quedó en
/// la caché local.
///
/// Distingue dos situaciones que la UI y el repositorio tratan distinto:
/// - [location] != null: hay una última posición conocida y se puede
///   enviar al backend.
/// - [location] == null: el estado guardado es "sin ubicación" (el
///   permiso no está concedido o se revocó). No se envía nada.
class CachedLocation {
  const CachedLocation({this.location, required this.updatedAt});

  final UserLocation? location;

  /// Cuándo se guardó este estado (no necesariamente cuándo se obtuvo la
  /// posición: para eso está `location.capturedAt`).
  final DateTime updatedAt;

  bool get isAvailable => location != null;
}
