import 'package:flutter/material.dart';

/// Indicador de carga reutilizable.
///
/// Usado en `rooms_list_screen.dart` y `room_detail_screen.dart` mientras
/// se espera la respuesta del backend. En `login_screen.dart` y
/// `register_screen.dart` se usa un `CircularProgressIndicator` inline
/// más chico dentro del botón, ya que este widget está pensado para
/// ocupar toda la pantalla.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
