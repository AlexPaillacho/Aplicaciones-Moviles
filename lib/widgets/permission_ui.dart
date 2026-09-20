import 'package:flutter/material.dart';
import '../core/tokens.dart';
import 'app_button.dart';

/// Muestra una explicación breve de para qué se usa un permiso, ANTES de
/// que el sistema muestre su propio diálogo (Taller Semana 14, Fase 3).
///
/// Devuelve `true` si el usuario decide continuar y `false` si elige
/// "Ahora no" o cierra el diálogo. Si devuelve `false` la pantalla NO
/// debe pedir el permiso: así el usuario nunca ve el diálogo del
/// sistema sin contexto, y "Ahora no" no cuenta como una denegación.
Future<bool> showPermissionRationaleDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Continuar',
  String cancelLabel = 'Ahora no',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Aviso para un permiso (o servicio del sistema) que no está
/// disponible: explica qué pasa y, si hay algo que el usuario pueda
/// hacer, ofrece UNA acción (pedir de nuevo, abrir Ajustes, etc.).
///
/// No conoce ningún permiso concreto: la pantalla decide el texto, el
/// ícono y la acción según el estado (denied / permanentlyDenied /
/// restricted / GPS apagado). Sin [onAction] solo informa, por ejemplo
/// cuando el permiso está restringido y no hay nada que la app pueda
/// hacer.
///
/// ### Interfaz pública
/// | Prop | Tipo | Descripción |
/// |---|---|---|
/// | message | String | qué pasa y por qué importa |
/// | icon | IconData | ícono que acompaña el mensaje |
/// | actionLabel | String? | texto del botón; sin él no hay botón |
/// | actionIcon | IconData? | ícono opcional del botón |
/// | onAction | VoidCallback? | acción del botón |
class PermissionNotice extends StatelessWidget {
  const PermissionNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;

    // liveRegion: los lectores de pantalla anuncian el aviso cuando
    // aparece o cambia de estado (ej. de "denegado" a "Abrir Ajustes").
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppTokens.spaceSM),
        decoration: BoxDecoration(
          color: AppTokens.colorPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: AppTokens.colorPrimary),
                const SizedBox(width: AppTokens.spaceSM),
                Expanded(child: Text(message, style: AppTokens.textBody)),
              ],
            ),
            if (hasAction) ...[
              const SizedBox(height: AppTokens.spaceSM),
              AppButton(
                label: actionLabel!,
                icon: actionIcon,
                variant: AppButtonVariant.secondary,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
