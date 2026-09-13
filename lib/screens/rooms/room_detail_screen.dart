import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/tokens.dart';
import '../../models/room.dart';
import '../../services/api_service.dart';
import '../../services/recorder_service.dart';
import '../../data/rooms_remote_source.dart';
import '../../state/auth_provider.dart';
import '../../state/rooms_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/status_view.dart';

/// Taller Semana 12: el detalle ahora lee la sala desde el
/// `RoomsProvider` (caché local + cola offline), no directamente del
/// backend — así la edición de nombre/estado funciona sin conexión
/// (queda encolada y se sincroniza sola) y muestra el ícono de
/// "pendiente de sincronizar" mientras tanto. `delete` sigue yendo
/// directo al backend: el taller solo pide offline para lectura,
/// creación y edición.
class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final int roomId;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final _roomsService = RoomsRemoteSource(ApiService.instance);
  final _recorderService = RecorderService();

  bool _deleting = false;
  String? _error;

  bool _isRecording = false;
  bool _isUploading = false;
  bool _isProcessing = false;
  String? _audioStatusMessage;
  Map<String, dynamic>? _taskResult;

  @override
  void dispose() {
    _recorderService.dispose();
    super.dispose();
  }

  Room? _findRoom(BuildContext context) {
    final rooms = context.watch<RoomsProvider>().rooms;
    for (final r in rooms) {
      if (r.id == widget.roomId) return r;
    }
    return null;
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await _roomsService.deleteRoom(widget.roomId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _error = 'No se pudo eliminar: $e';
        _deleting = false;
      });
    }
  }

  Future<void> _showEditDialog(Room room) async {
    final controller = TextEditingController(text: room.name);
    var active = room.active;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editar sala'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(controller: controller, label: 'Nombre de la sala'),
              const SizedBox(height: AppTokens.spaceMD),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activa'),
                value: active,
                onChanged: (v) => setDialogState(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final name = controller.text.trim();
      // Si estamos sin conexión, esto queda encolado y se aplica de
      // inmediato en la caché (optimista); se sincroniza solo al
      // reconectar.
      await context.read<RoomsProvider>().update(
            room,
            name: name.isEmpty ? null : name,
            active: active,
          );
    }
  }

  Future<void> _startRecording() async {
    setState(() {
      _audioStatusMessage = null;
      _taskResult = null;
    });
    try {
      await _recorderService.start();
      setState(() => _isRecording = true);
    } catch (e) {
      setState(() => _audioStatusMessage = 'No se pudo iniciar la grabación: $e');
    }
  }

  Future<void> _stopAndSend() async {
    setState(() => _isRecording = false);

    final File? audioFile = await _recorderService.stop();
    if (audioFile == null) {
      setState(() => _audioStatusMessage = 'No se grabó ningún audio.');
      return;
    }

    setState(() {
      _isUploading = true;
      _audioStatusMessage = 'Enviando audio al backend...';
    });

    try {
      final response = await _roomsService.processAudio(widget.roomId, audioFile);
      final taskId = response['task_id'] as String;
      setState(() {
        _isUploading = false;
        _isProcessing = true;
        _audioStatusMessage = 'Procesando (task_id: $taskId)...';
      });
      await _pollTaskStatus(taskId);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _isProcessing = false;
        _audioStatusMessage = 'Error al enviar el audio: $e';
      });
    }
  }

  Future<void> _pollTaskStatus(String taskId) async {
    const maxAttempts = 10;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      try {
        final status = await _roomsService.getTaskStatus(taskId);
        final state = status['state'] as String?;

        if (state == 'SUCCESS') {
          setState(() {
            _isProcessing = false;
            _taskResult = status['result'] as Map<String, dynamic>?;
            _audioStatusMessage = 'Procesamiento completado.';
          });
          return;
        }
        if (state == 'FAILURE') {
          setState(() {
            _isProcessing = false;
            _audioStatusMessage = 'El procesamiento falló: ${status['error']}';
          });
          return;
        }
        setState(() => _audioStatusMessage = 'Procesando... ($state)');
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _audioStatusMessage = 'Error consultando el estado: $e';
        });
        return;
      }
    }
    setState(() {
      _isProcessing = false;
      _audioStatusMessage = 'Tiempo de espera agotado consultando el resultado.';
    });
  }

  Widget _buildAudioSection() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Práctica de audio', style: AppTokens.textTitle),
          const SizedBox(height: AppTokens.spaceMD),
          AppButton(
            label: _isRecording ? 'Detener y enviar' : 'Grabar',
            icon: _isRecording ? Icons.stop : Icons.mic,
            loading: _isUploading || _isProcessing,
            onPressed: _isRecording ? _stopAndSend : _startRecording,
            variant: _isRecording
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
          ),
          if (_audioStatusMessage != null) ...[
            const SizedBox(height: AppTokens.spaceMD),
            Text(_audioStatusMessage!, style: AppTokens.textBody),
          ],
          if (_taskResult != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.spaceSM),
              decoration: BoxDecoration(
                color: AppTokens.colorSuccessContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: Text(
                'Resultado: $_taskResult',
                style: const TextStyle(color: AppTokens.colorOnSuccessContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<AuthProvider>().currentUser;
    final room = _findRoom(context);
    final isHost = room != null && room.hostId == currentUser?.id;
    final roomsLoading = context.watch<RoomsProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(room?.name ?? 'Sala')),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: StatusView(
          loading: roomsLoading && room == null,
          error: _error,
          onRetry: () => context.read<RoomsProvider>().refresh(),
          isEmpty: room == null,
          emptyMessage:
              'Esta sala todavía no está en la caché local. Conéctate y reintenta.',
          builder: (context) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Host: ${room!.hostUsername ?? '-'}',
                                style: AppTokens.textBody),
                          ),
                          if (room.pendingSync)
                            Row(
                              children: [
                                const Icon(Icons.sync,
                                    size: 16, color: AppTokens.colorPrimary),
                                const SizedBox(width: AppTokens.spaceXS),
                                Text('Pendiente de sincronizar',
                                    style: AppTokens.textCaption),
                              ],
                            ),
                        ],
                      ),
                      Text('Estado: ${room.active ? 'Activa' : 'Inactiva'}',
                          style: AppTokens.textBody),
                      if (isHost) ...[
                        const SizedBox(height: AppTokens.spaceMD),
                        AppButton(
                          label: 'Editar sala',
                          icon: Icons.edit,
                          onPressed: () => _showEditDialog(room),
                        ),
                        const SizedBox(height: AppTokens.spaceSM),
                        AppButton(
                          label: _deleting ? 'Eliminando...' : 'Eliminar sala',
                          icon: Icons.delete,
                          loading: _deleting,
                          variant: AppButtonVariant.destructive,
                          onPressed: _delete,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMD),
                _buildAudioSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
