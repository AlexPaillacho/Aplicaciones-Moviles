import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_provider.dart';
import '../../state/rooms_provider.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_indicator.dart';
import 'room_detail_screen.dart';

/// Lista de salas.
///
/// `ListView` con nombre/estado, pull-to-refresh, y un
/// `FloatingActionButton` que abre un diálogo simple para crear sala.
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

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final roomsProvider = context.read<RoomsProvider>();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nueva sala'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre de la sala'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty || !mounted) return;

    try {
      await roomsProvider.create(name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear la sala')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsProvider = context.watch<RoomsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salas'),
        actions: [
          IconButton(
            onPressed: () => context.read<AuthProvider>().logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: roomsProvider.refresh,
        child: _buildBody(roomsProvider),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        tooltip: 'Crear sala',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(RoomsProvider roomsProvider) {
    if (roomsProvider.isLoading && roomsProvider.rooms.isEmpty) {
      return const LoadingIndicator();
    }

    if (roomsProvider.errorMessage != null && roomsProvider.rooms.isEmpty) {
      return ListView(
        children: [ErrorBanner(message: roomsProvider.errorMessage!)],
      );
    }

    if (roomsProvider.rooms.isEmpty) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No hay salas todavía')),
          ),
        ],
      );
    }

    return ListView.builder(
      itemCount: roomsProvider.rooms.length,
      itemBuilder: (context, index) {
        final room = roomsProvider.rooms[index];
        return ListTile(
          title: Text(room.name),
          subtitle: Text(room.active ? 'Activa' : 'Inactiva'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RoomDetailScreen(roomId: room.id)),
            );
          },
        );
      },
    );
  }
}
