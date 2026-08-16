import 'package:flutter/material.dart';

/// Tema visual de la app. Centralizado aquí para no repetir
/// configuración de `ThemeData` en `app.dart`.
ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
    useMaterial3: true,
  );
}
