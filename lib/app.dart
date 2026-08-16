import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'state/auth_provider.dart';

/// Widget raíz de la app.
///
/// Provee `AuthProvider` a todo el árbol y define las rutas nombradas
/// `/login`, `/register`, `/home`. La ruta inicial es `AuthGate`, que
/// decide a dónde ir según si hay una sesión restaurable.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: 'Speak English',
        theme: buildAppTheme(),
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const HomeScreen(title: 'Speak English'),
        },
      ),
    );
  }
}

/// Decide la pantalla inicial según el estado de `AuthProvider`.
///
/// Al montarse, intenta restaurar la sesión (`GET /auth/me` con el
/// token guardado, si existe). Mientras eso ocurre, muestra un loader.
/// Cuando termina: si quedó autenticado, muestra `HomeScreen`; si no,
/// `LoginScreen`.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().tryRestoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return authProvider.isAuthenticated
        ? const HomeScreen(title: 'Speak English')
        : const LoginScreen();
  }
}
