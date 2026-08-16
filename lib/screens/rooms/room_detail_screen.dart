import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../models/room.dart';
import '../../services/api_service.dart';
import '../../services/rooms_service.dart';
import '../../state/auth_provider.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/loading_indicator.dart';

/// Detalle de una sala.
///
/// Botón "Eliminar" visible solo si `room.hostId == currentUser.id`.
/// Fase 4: graba audio con `package:record`, lo envía a
/// `POST /rooms/<id>/process-audio` y hace polling a
/// `GET /tasks/<task_id>` (cada 2s, máx. 10 intentos) hasta obtener
/// `SUCCESS`/`FAILURE`.
class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final int roomId;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  final _roomsService = RoomsService(ApiService());
  final _recorder = AudioRecorder();

  Room? _room;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDeleting = false;

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _audioStatusMessage;
  Map<String, dynamic>? _taskResult;

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
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
    } on UnauthorizedException {
      // El logout y la navegación a /login ya se disparan de forma
      // centralizada en ApiService.onUnauthorized.
    } on RoomException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Ocurrió un error inesperado');
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
    } on UnauthorizedException {
      // El logout y la navegación a /login ya se disparan de forma
      // centralizada en ApiService.onUnauthorized.
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo eliminar la sala')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path != null) {
        await _sendAudio(File(path));
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se necesita permiso de micrófono')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/room_${widget.roomId}_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    setState(() => _isRecording = true);
  }

  Future<void> _sendAudio(File audioFile) async {
    setState(() {
      _isProcessing = true;
      _taskResult = null;
      _audioStatusMessage = 'Enviando audio...';
    });

    try {
      final data = await _roomsService.processAudio(widget.roomId, audioFile);
      final taskId = data['task_id'] as String;
      if (!mounted) return;
      setState(() => _audioStatusMessage = 'Procesando...');
      await _pollTaskStatus(taskId);
    } on UnauthorizedException {
      // El logout y la navegación a /login ya se disparan de forma
      // centralizada en ApiService.onUnauthorized.
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _audioStatusMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _audioStatusMessage = 'No se pudo enviar el audio';
      });
    }
  }

  /// Polling a `GET /tasks/<task_id>` cada 2 segundos, máximo 10 intentos,
  /// hasta recibir `state == "SUCCESS"` o `"FAILURE"`.
  Future<void> _pollTaskStatus(String taskId) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      try {
        final status = await _roomsService.getTaskStatus(taskId);
        final state = status['state'] as String?;

        if (state == 'SUCCESS') {
          setState(() {
            _isProcessing = false;
            _taskResult = status['result'] as Map<String, dynamic>?;
            _audioStatusMessage = null;
          });
          return;
        }

        if (state == 'FAILURE') {
          setState(() {
            _isProcessing = false;
            _audioStatusMessage = 'Error al procesar el audio';
          });
          return;
        }
      } on UnauthorizedException {
        // El logout y la navegación a /login ya se disparan de forma
        // centralizada en ApiService.onUnauthorized; no tiene sentido
        // seguir reintentando.
        setState(() => _isProcessing = false);
        return;
      } catch (_) {
        // Se reintenta en el próximo intento del loop.
      }
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _audioStatusMessage = 'El procesamiento está tardando más de lo esperado';
    });
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
          const SizedBox(height: 24),
          _buildRecordingSection(),
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

  Widget _buildRecordingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: _isProcessing ? null : _toggleRecording,
          icon: Icon(_isRecording ? Icons.stop : Icons.mic),
          label: Text(_isRecording ? 'Detener grabación' : 'Grabar práctica'),
        ),
        if (_isProcessing) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(_audioStatusMessage ?? 'Procesando...'),
            ],
          ),
        ],
        if (!_isProcessing && _audioStatusMessage != null) ...[
          const SizedBox(height: 12),
          Text(_audioStatusMessage!),
        ],
        if (_taskResult != null) ...[
          const SizedBox(height: 12),
          Text('Resultado: ${_taskResult!['status']}'),
          if (_taskResult!['detail'] != null) Text('${_taskResult!['detail']}'),
        ],
      ],
    );
  }
}
