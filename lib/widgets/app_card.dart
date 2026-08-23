import 'package:flutter/material.dart';
import '../core/tokens.dart';

/// Contenedor reutilizable con la superficie, el radio y el padding
/// estándar de la app. No conoce el backend ni navega por sí mismo:
/// solo expone [onTap] como callback, la pantalla decide qué hacer.
///
/// ### Por qué se abstrae (regla de las 3 apariciones)
/// Se repite igual en: la lista de salas (una card por sala), el panel
/// de información de una sala en el detalle, y el formulario de
/// login/registro (como contenedor del form). Sin este componente, el
/// radio/padding/color de esas tres superficies se iría desincronizando
/// con cada cambio de diseño.
///
/// ### Interfaz pública
/// | Prop | Tipo | Descripción |
/// |---|---|---|
/// | child | Widget | contenido delegado (slot) |
/// | onTap | VoidCallback? | callback opcional; si es null, la card no es interactiva |
/// | semanticLabel | String? | etiqueta para lectores de pantalla cuando [onTap] está presente |
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.colorBorder),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        // Garantiza el área táctil mínima de 48dp aunque el contenido
        // interno sea más chico (ej. una card angosta).
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppTokens.minTouchTarget),
          child: content,
        ),
      ),
    );
  }
}
