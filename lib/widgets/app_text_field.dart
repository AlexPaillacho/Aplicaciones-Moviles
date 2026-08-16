import 'package:flutter/material.dart';

/// Campo de texto estilizado reutilizable para formularios.
///
/// Stub de la Fase 1. Se usa a partir de la Fase 2 en login/registro.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}
