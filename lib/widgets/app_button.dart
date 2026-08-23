import 'package:flutter/material.dart';
import '../core/tokens.dart';

enum AppButtonVariant { primary, secondary, destructive }

/// Botón reutilizable con estado de carga incorporado (evita que cada
/// pantalla tenga que combinar a mano un ElevatedButton + spinner) y
/// tamaño mínimo garantizado de 48dp de alto para cumplir el área
/// táctil accesible. No conoce el backend: [onPressed] es un callback
/// simple, la pantalla decide qué hacer al presionar.
///
/// ### Por qué se abstrae (regla de las 3 apariciones)
/// Aparece en login, registro, "crear sala", "eliminar sala" y "grabar
/// audio". Antes de este catálogo cada pantalla armaba su propio
/// `SizedBox(18,18,CircularProgressIndicator)` para el estado de carga,
/// con tamaños ligeramente distintos entre pantallas.
///
/// ### Interfaz pública
/// | Prop | Tipo | Descripción |
/// |---|---|---|
/// | label | String | texto del botón |
/// | onPressed | VoidCallback? | callback; si es null, el botón queda deshabilitado |
/// | loading | bool | si es true, muestra spinner y bloquea el tap |
/// | variant | AppButtonVariant | primary / secondary / destructive |
/// | icon | IconData? | ícono opcional antes del texto |
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final AppButtonVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground) = switch (variant) {
      AppButtonVariant.primary => (scheme.primary, scheme.onPrimary),
      AppButtonVariant.secondary => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer
        ),
      AppButtonVariant.destructive => (
          scheme.errorContainer,
          scheme.onErrorContainer
        ),
    };

    final child = loading
        ? SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: AppTokens.spaceSM),
              ],
              Text(label),
            ],
          );

    return Semantics(
      button: true,
      enabled: onPressed != null && !loading,
      label: loading ? '$label, cargando' : label,
      child: SizedBox(
        height: AppTokens.minTouchTarget,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: background.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusButton),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
