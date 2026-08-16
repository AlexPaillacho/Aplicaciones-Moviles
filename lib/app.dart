import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/rooms/rooms_list_screen.dart';
import 'state/auth_provider.dart';
import 'state/rooms_provider.dart';

/// Widget raíz de la app.
///
/// Provee `AuthProvider` y `RoomsProvider` a todo el árbol y define las
/// rutas nombradas `/login`, `/register`, `/home`. La ruta inicial es
/// `AuthGate`, que decide a dónde ir según si hay una sesión restaurable.
/// A partir de la Fase 3, la pantalla principal tras login es
/// `RoomsListScreen`.
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RoomsProvider()),
      ],
      child: MaterialApp(
        title: 'Speak English',
        theme: buildAppTheme(),
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/home': (_) => const RoomsListScreen(),
        },
      ),
    );
  }
}

/// Decide la pantalla inicial según el estado de `AuthProvider`.
///
/// Al montarse, intenta restaurar la sesión (`GET /auth/me` con el
/// token guardado, si existe). Mientras eso ocurre, muestra un loader.
/// Cuando termina: si quedó autenticado, muestra `RoomsListScreen`;
/// si no, `LoginScreen`.
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

    return authProvider.isAuthenticated ? const RoomsListScreen() : const LoginScreen();
  }
}
