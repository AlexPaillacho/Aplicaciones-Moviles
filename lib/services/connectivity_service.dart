import 'package:connectivity_plus/connectivity_plus.dart';

/// Wrapper delgado sobre `connectivity_plus`.
///
/// Nota importante para la demo del taller: esto detecta que el
/// dispositivo tiene una interfaz de red activa (wifi/datos), NO que el
/// backend Flask sea alcanzable. Para probar "sin conexión" se usa el
/// modo avión del dispositivo (como piden las recomendaciones del
/// taller), no apagar solo el servidor: apagar el servidor mientras el
/// wifi sigue activo no dispara este stream, y el error se vería recién
/// al fallar la petición HTTP (`NetworkException`), no antes.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _hasConnection(results);
  }

  /// Emite `true` cada vez que el dispositivo pasa a tener conexión
  /// (de ninguna interfaz a alguna). `app.dart` escucha esto para
  /// disparar la sincronización de la cola pendiente.
  Stream<bool> get onConnectivityRestored {
    return _connectivity.onConnectivityChanged
        .map(_hasConnection)
        .where((isOnline) => isOnline);
  }

  bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
