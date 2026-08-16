import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/room.dart';
import '../../services/api_service.dart';
import '../../services/rooms_service.dart';
import '../../state/auth_provider.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_indicator.dart';

/// Detalle de una sala.
///
/// Botón "Eliminar" visible solo si `room.hostId == currentUser.id`.
/// La grabación y envío de audio se agrega en la Fase 4.
class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final int roomId;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final _roomsService = RoomsService(ApiService());

  Room? _room;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  Future<void> _loadRoom() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final room = await _roomsService.getRoom(widget.roomId);
      if (!mounted) return;
      setState(() => _room = room);
    } on RoomException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo conectar al servidor');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRoom() async {
    setState(() => _isDeleting = true);
    try {
      await _roomsService.deleteRoom(widget.roomId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la sala')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final room = _room;
    final isHost = room != null && currentUser != null && room.hostId == currentUser.id;

    return Scaffold(
      appBar: AppBar(title: Text(room?.name ?? 'Sala')),
      body: _buildBody(room, isHost),
    );
  }

  Widget _buildBody(Room? room, bool isHost) {
    if (_isLoading) return const LoadingIndicator();
    if (_errorMessage != null) return ErrorBanner(message: _errorMessage!);
    if (room == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estado: ${room.active ? 'Activa' : 'Inactiva'}'),
          const SizedBox(height: 8),
          Text('Host: ${room.hostUsername ?? '—'}'),
          const Spacer(),
          if (isHost)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isDeleting ? null : _deleteRoom,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: _isDeleting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Eliminar'),
              ),
            ),
        ],
      ),
    );
  }
}
