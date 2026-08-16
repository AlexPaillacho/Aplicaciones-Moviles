import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/home/home_screen.dart';

/// Widget raíz de la app.
///
/// En la Fase 1 apunta directo a `HomeScreen` (el demo del taller).
/// En la Fase 2 se agregan rutas nombradas `/login`, `/register`,
/// `/home` y la lógica de arranque (¿hay token guardado?).
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak English',
      theme: buildAppTheme(),
      home: const HomeScreen(title: 'Speak English'),
    );
  }
}
