import 'package:flutter/material.dart';
import '../core/tokens.dart';

/// Envuelve cualquier contenido que dependa de datos remotos y resuelve
/// de forma explícita sus tres estados no felices: cargando, vacío y
/// error. No sabe de dónde vienen los datos (no llama a ApiService ni a
/// ningún *Service*): la pantalla le pasa banderas y callbacks.
///
/// ### Por qué se abstrae (regla de las 3 apariciones)
/// La lista de salas, el detalle de una sala y el flujo de envío/estado
/// de audio necesitan exactamente esta misma lógica (mostrar spinner,
/// mostrar "no hay datos" o mostrar el error con botón de reintentar).
/// Repetirla en cada pantalla ya había producido inconsistencias (ver
/// Fase 5 del proyecto, antes de este catálogo).
///
/// ### Interfaz pública
/// | Prop | Tipo | Descripción |
/// |---|---|---|
/// | loading | bool | si es true, se muestra el estado de carga |
/// | error | String? | si no es null (y loading es false), se muestra el estado de error |
/// | isEmpty | bool | si es true (y no hay loading/error), se muestra el estado vacío |
/// | onRetry | VoidCallback? | callback del botón "Reintentar" en el estado de error |
/// | emptyMessage | String | texto del estado vacío |
/// | builder | WidgetBuilder | contenido delegado (slot) que se muestra cuando no aplica ninguno de los tres estados |
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.loading,
    required this.isEmpty,
    required this.builder,
    this.error,
    this.onRetry,
    this.emptyMessage = 'No hay datos para mostrar.',
  });

  final bool loading;
  final String? error;
  final bool isEmpty;
  final VoidCallback? onRetry;
  final String emptyMessage;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppTokens.spaceXL),
          child: Semantics(
            label: 'Cargando contenido',
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (error != null) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLG),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  color: scheme.error, size: AppTokens.spaceXL),
              const SizedBox(height: AppTokens.spaceSM),
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: AppTokens.textBody,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppTokens.spaceMD),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppTokens.minTouchTarget,
                  ),
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLG),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: AppTokens.textCaption,
          ),
        ),
      );
    }

    return builder(context);
  }
}
