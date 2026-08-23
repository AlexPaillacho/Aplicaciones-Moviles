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
class RoomsListScreen extends StatelessWidget {
  const RoomsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RoomsProvider()..refresh(),
      child: const _RoomsListView(),
    );
  }
}

class _RoomsListView extends StatefulWidget {
  const _RoomsListView();

  @override
  State<_RoomsListView> createState() => _RoomsListViewState();
}

class _RoomsListViewState extends State<_RoomsListView> {
  bool _creating = false;

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    final provider = context.read<RoomsProvider>();

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
      await provider.create(name);
      if (mounted) setState(() => _creating = false);
    }
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
                  loading: rooms.loading && rooms.rooms.isEmpty,
                  error: rooms.error,
                  onRetry: rooms.refresh,
                  isEmpty: rooms.rooms.isEmpty,
                  emptyMessage: 'Todavía no hay salas. Crea la primera.',
                  builder: (context) => ListView.separated(
                    itemCount: rooms.rooms.length,
                    separatorBuilder: (_, __) =>
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
