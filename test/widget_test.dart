// Fase 6: reemplaza el smoke test del contador (que probaba el demo de
// conectividad del taller, ya movido a screens/home/home_screen.dart y
// fuera de las rutas de la app real).
//
// Verifica que login_screen renderiza los campos email/password y el
// botón "Ingresar", sin depender de la red: AuthProvider se monta con
// sus valores por defecto (isLoading == false) y el test nunca toca el
// botón, así que no dispara ninguna llamada HTTP real.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:speak_english/screens/auth/login_screen.dart';
import 'package:speak_english/state/auth_provider.dart';
import 'package:speak_english/widgets/app_text_field.dart';

void main() {
  testWidgets('LoginScreen renderiza email, contraseña y el botón Ingresar',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    // Dos campos de texto: email y contraseña.
    expect(find.byType(AppTextField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);

    // Botón "Ingresar" (distinto del título del AppBar, que dice lo mismo).
    expect(find.widgetWithText(ElevatedButton, 'Ingresar'), findsOneWidget);

    // Enlace a registro.
    expect(find.text('¿No tienes cuenta? Regístrate'), findsOneWidget);
  });
}
