import 'package:flutter/material.dart';
import '../core/tokens.dart';

/// Campo de texto reutilizable con etiqueta, texto de error opcional y
/// Semantics explícito (algunos lectores de pantalla no infieren bien
/// el label de un InputDecoration anidado). No valida reglas de negocio
/// ni llama al backend: la pantalla decide qué mostrar en [errorText].
///
/// ### Por qué se abstrae (regla de las 3 apariciones)
/// Usado en login (email, contraseña), registro (usuario, email,
/// contraseña) y en el diálogo de "crear sala" del catálogo de salas.
///
/// ### Interfaz pública
/// | Prop | Tipo | Descripción |
/// |---|---|---|
/// | controller | TextEditingController | fuente de verdad del texto |
/// | label | String | etiqueta visible y semántica |
/// | obscureText | bool | oculta el texto (contraseñas) |
/// | keyboardType | TextInputType? | tipo de teclado sugerido |
/// | errorText | String? | mensaje de error mostrado bajo el campo |
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: label,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: AppTokens.textBodyLarge,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
        ),
      ),
    );
  }
}
