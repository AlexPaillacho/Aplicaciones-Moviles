import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/rooms/rooms_list_screen.dart';
import 'services/api_service.dart';
import 'state/auth_provider.dart';
import 'state/rooms_provider.dart';

/// Navigator global: permite navegar (ej. a `/login`) desde fuera del
/// árbol de widgets, como el manejo centralizado de 401 en
/// `ApiService.onUnauthorized` (Fase 5).
final navigatorKey = GlobalKey<NavigatorState>();

/// Widget raíz de la app.
///
/// Provee `AuthProvider` y `RoomsProvider` a todo el árbol y define las
/// rutas nombradas `/login`, `/register`, `/home`. La ruta inicial es
/// `AuthGate`, que decide a dónde ir según si hay una sesión restaurable.
///
/// Fase 5: `App` pasó a ser `StatefulWidget` para poder configurar, una
/// única vez, `ApiService.onUnauthorized` apuntando a la misma instancia
/// de `AuthProvider` que usa el resto de la app (logout + navegar a
/// `/login` sin importar desde qué pantalla vino el 401).
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _authProvider = AuthProvider();
  final _roomsProvider = RoomsProvider();

  @override
  void initState() {
    super.initState();
    ApiService.onUnauthorized = () {
      _authProvider.logout();
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _roomsProvider),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
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
