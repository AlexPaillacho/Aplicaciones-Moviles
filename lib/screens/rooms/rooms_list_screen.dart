import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/tokens.dart';
import '../../state/auth_provider.dart';
import '../../state/rooms_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/status_view.dart';
import 'room_detail_screen.dart';

/// Pantalla real ensamblada exclusivamente con componentes del catálogo:
/// AppCard (una por sala), StatusView (loading/empty/error del listado)
/// y AppButton + AppTextField (diálogo de creación). Corresponde al
/// endpoint GET /rooms/list (y POST /rooms para la creación).
///
/// Taller Semana 12: usa el `RoomsProvider` GLOBAL (provisto en
/// `app.dart`), no uno propio — es el mismo que `app.dart` usa para
/// disparar la sincronización al reconectar y para limpiar la caché al
/// hacer logout, así que tiene que ser una única instancia compartida.
class RoomsListScreen extends StatefulWidget {
  const RoomsListScreen({super.key});

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

class _RoomsListScreenState extends State<RoomsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomsProvider>().refresh();
    });
  }

  bool _creating = false;

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    final provider = context.read<RoomsProvider>();
    final currentUser = context.read<AuthProvider>().currentUser;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva sala'),
        content: AppTextField(controller: controller, label: 'Nombre de la sala'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _creating = true);
      await provider.create(
        name,
        hostId: currentUser?.id,
        hostUsername: currentUser?.username,
      );
      if (mounted) setState(() => _creating = false);
    }
  }

  String _formatLastSynced(DateTime? lastSyncedAt) {
    if (lastSyncedAt == null) return 'Sin datos sincronizados todavía';
    final diff = DateTime.now().difference(lastSyncedAt);
    if (diff.inMinutes < 1) return 'Actualizado hace instantes';
    if (diff.inMinutes < 60) return 'Actualizado hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Actualizado hace ${diff.inHours} h';
    return 'Actualizado hace ${diff.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomsProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salas'),
        actions: [
          Semantics(
            button: true,
            label: 'Cerrar sesión',
            child: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => context.read<AuthProvider>().logout(),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rooms.isOffline || rooms.pendingCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTokens.spaceSM),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppTokens.spaceSM),
                    decoration: BoxDecoration(
                      color: AppTokens.colorPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          rooms.isOffline ? Icons.cloud_off : Icons.sync,
                          size: 18,
                          color: AppTokens.colorPrimary,
                        ),
                        const SizedBox(width: AppTokens.spaceSM),
                        Expanded(
                          child: Text(
                            rooms.isOffline
                                ? '${_formatLastSynced(rooms.lastSyncedAt)} · Sin conexión'
                                : '${rooms.pendingCount} cambio(s) por sincronizar',
                            style: AppTokens.textCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            AppButton(
              label: 'Nueva sala',
              icon: Icons.add,
              loading: _creating,
              onPressed: () => _showCreateDialog(context),
            ),
            const SizedBox(height: AppTokens.spaceMD),
            Expanded(
              child: RefreshIndicator(
                onRefresh: rooms.refresh,
                child: StatusView(
                  loading: rooms.isLoading && rooms.rooms.isEmpty,
                  error: rooms.errorMessage,
                  onRetry: rooms.refresh,
                  isEmpty: rooms.rooms.isEmpty,
                  emptyMessage: 'Todavía no hay salas. Crea la primera.',
                  builder: (context) => ListView.separated(
                    itemCount: rooms.rooms.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppTokens.spaceSM),
                    itemBuilder: (context, index) {
                      final room = rooms.rooms[index];
                      final isHost = room.hostId == auth.currentUser?.id;
                      return AppCard(
                        semanticLabel: 'Abrir sala ${room.name}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RoomDetailScreen(roomId: room.id),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(room.name, style: AppTokens.textBodyLarge),
                                  const SizedBox(height: AppTokens.spaceXS),
                                  Text(
                                    'Host: ${room.hostUsername ?? '-'} · '
                                    '${room.active ? 'Activa' : 'Inactiva'}',
                                    style: AppTokens.textCaption,
                                  ),
                                ],
                              ),
                            ),
                            if (room.pendingSync)
                              const Padding(
                                padding: EdgeInsets.only(right: AppTokens.spaceXS),
                                child: Icon(Icons.sync,
                                    size: 18, color: AppTokens.colorPrimary),
                              ),
                            if (isHost)
                              const Icon(Icons.star,
                                  size: 18, color: AppTokens.colorPrimary),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
