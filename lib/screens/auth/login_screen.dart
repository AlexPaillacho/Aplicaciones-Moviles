import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/tokens.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../state/auth_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/status_view.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();

    try {
      await auth.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pushReplacementNamed('/home');
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } on ValidationException catch (e) {
      // Bloque 7, familia 4 (422): datos inválidos, distinto de
      // credenciales incorrectas (`AuthException`, 401).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } on NetworkException catch (e) {
      // Bloque 7, familias 1-3: cada subtipo (sin conexión / timeout /
      // servidor caído) ya trae su propio mensaje de dominio.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ocurrió un error inesperado';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.spaceLG),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Speak English', style: AppTokens.textHeadline),
                const SizedBox(height: AppTokens.spaceLG),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTokens.spaceMD),
                    child: StatusView(
                      loading: false,
                      isEmpty: false,
                      error: _error,
                      builder: (_) => const SizedBox.shrink(),
                    ),
                  ),
                AppTextField(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppTokens.spaceSM),
                AppTextField(
                  controller: _passwordController,
                  label: 'Contraseña',
                  obscureText: true,
                ),
                const SizedBox(height: AppTokens.spaceLG),
                AppButton(
                  label: 'Ingresar',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppTokens.spaceSM),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).pushNamed('/register'),
                  child: const Text('¿No tienes cuenta? Regístrate'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
