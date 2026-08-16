import 'package:flutter/material.dart';

/// Indicador de carga reutilizable.
///
/// Stub de la Fase 1. Se usa a partir de la Fase 5 en login, lista de
/// salas, detalle y grabación.
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
