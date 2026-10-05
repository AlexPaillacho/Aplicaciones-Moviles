import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/tokens.dart';
import '../../models/room.dart';
import '../../services/api_service.dart';
import '../../services/permission_service.dart';
import '../../services/recorder_service.dart';
import '../../data/rooms_remote_source.dart';
import '../../state/auth_provider.dart';
import '../../state/rooms_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/permission_ui.dart';
import '../../widgets/room_form_dialog.dart';
import '../../widgets/status_view.dart';
import 'submissions_screen.dart';

/// Taller Semana 12: el detalle ahora lee la sala desde el
/// `RoomsProvider` (caché local + cola offline), no directamente del
/// backend — así la edición de nombre/estado funciona sin conexión
/// (queda encolada y se sincroniza sola) y muestra el ícono de
/// "pendiente de sincronizar" mientras tanto. `delete` sigue yendo
/// directo al backend: el taller solo pide offline para lectura,
/// creación y edición.
///
/// Taller Semana 14 (Fase 3): el permiso de micrófono se pide en el
/// momento de uso (al pulsar "Grabar", nunca al abrir la app),
/// precedido de una explicación. Según el estado del permiso:
/// - *denied*: "Grabar" queda deshabilitado + botón para pedirlo de
///   nuevo (con la explicación otra vez).
/// - *permanentlyDenied*: "Grabar" deshabilitado + botón "Abrir
///   Ajustes"; al volver a la app se vuelve a comprobar el permiso.
/// - *restricted*: "Grabar" deshabilitado + mensaje informativo.
/// El resto de la sala (editar, eliminar, ver estado) funciona igual.
class RoomDetailScreen extends StatefulWidget {
  const RoomDetailScreen({super.key, required this.roomId});

  final int roomId;

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen>
    with WidgetsBindingObserver {
  final _roomsService = RoomsRemoteSource(ApiService.instance);
  final _permissionService = PermissionService();
  late final RecorderService _recorderService;

  bool _deleting = false;

  /// Estado del micrófono cuando NO se puede grabar; `null` = sin
  /// bloqueo conocido. En Android "nunca pedido" y "denegado una vez"
  /// llegan ambos como `denied`, así que `denied` solo se guarda aquí
  /// cuando el usuario realmente lo denegó en esta pantalla (en la
  /// primera visita el botón "Grabar" está habilitado y pide el permiso).
  AppPermissionStatus? _micBlockedStatus;

  /// true mientras hay un diálogo del sistema abierto: al cerrarse, la
  /// app pasa por `resumed` y no debemos re-comprobar a mitad de la
  /// solicitud.
  bool _requestingMic = false;

  bool _isRecording = false;
  bool _isUploading = false;
  String? _audioStatusMessage;

  /// true cuando el backend GUARDÓ el audio (respondió 202). Es
  /// independiente de si el procesamiento posterior (Celery) termina bien:
  /// el audio ya está guardado y aparece en el historial.
  bool _audioSent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recorderService = RecorderService(permissionService: _permissionService);
    // Solo COMPRUEBA el estado (no muestra ningún diálogo del sistema):
    // sirve para reflejar de entrada un bloqueo permanente o restringido.
    _refreshMicStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recorderService.dispose();
    super.dispose();
  }

  /// Al volver de Ajustes del sistema (caso: denegación permanente y el
  /// usuario concede el permiso desde ahí) se re-comprueba el permiso,
  /// para que "Grabar" se habilite sin reiniciar la app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshMicStatus();
  }

  Future<void> _refreshMicStatus() async {
    if (_requestingMic || _isRecording) return;
    final status = await _permissionService.checkMicrophone();
    if (!mounted) return;
    setState(() {
      switch (status) {
        case AppPermissionStatus.granted:
          _micBlockedStatus = null;
        case AppPermissionStatus.permanentlyDenied:
        case AppPermissionStatus.restricted:
          _micBlockedStatus = status;
        case AppPermissionStatus.denied:
          // Puede ser "nunca pedido": no se bloquea. Si el usuario ya lo
          // denegó en esta pantalla, `_micBlockedStatus` ya vale denied.
          break;
      }
    });
  }

  Future<bool> _confirmMicRationale() {
    return showPermissionRationaleDialog(
      context,
      title: 'Permiso de micrófono',
      message: 'Necesitamos el micrófono para grabar tu práctica de '
          'speaking en la sala. Solo grabamos cuando pulsas "Grabar".',
    );
  }

  /// Botón "Permitir micrófono" (estado denied): explica de nuevo y
  /// vuelve a pedir el permiso. No empieza a grabar: el usuario pulsa
  /// "Grabar" cuando esté listo.
  Future<void> _retryMicPermission() async {
    final accepted = await _confirmMicRationale();
    if (!accepted || !mounted) return;

    _requestingMic = true;
    try {
      final status = await _permissionService.requestMicrophone();
      if (!mounted) return;
      setState(() {
        _micBlockedStatus =
            status == AppPermissionStatus.granted ? null : status;
      });
    } finally {
      _requestingMic = false;
    }
  }

  Future<void> _openAppSettings() => _permissionService.openSettings();

  /// [listen] debe ser `true` SOLO dentro de `build` (para redibujar al
  /// cambiar la sala). En callbacks (ej. al abrir el historial) se usa
  /// `read`: llamar a `context.watch` fuera de `build` lanza "Tried to
  /// listen to a value exposed with provider, from outside of the widget
  /// tree" y el botón no hacía nada.
  Room? _findRoom(BuildContext context, {bool listen = false}) {
    final rooms = listen
        ? context.watch<RoomsProvider>().rooms
        : context.read<RoomsProvider>().rooms;
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
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  Future<void> _showEditDialog(Room room) async {
    final result = await showDialog<RoomFormResult>(
      context: context,
      builder: (_) => RoomFormDialog(
        title: 'Editar sala',
        confirmLabel: 'Guardar',
        initialName: room.name,
        initialActive: room.active,
      ),
    );
    if (result == null || !mounted) return;

    // Si estamos sin conexión, esto queda encolado y se aplica de
    // inmediato en la caché (optimista); se sincroniza solo al
    // reconectar.
    await context.read<RoomsProvider>().update(
          room,
          name: result.name.isEmpty ? null : result.name,
          active: result.active,
        );
  }

  Future<void> _startRecording() async {
    setState(() {
      _audioStatusMessage = null;
      _audioSent = false;
    });

    // Explicación ANTES del diálogo del sistema, y solo si el permiso
    // todavía hay que pedirlo. Si el usuario elige "Ahora no" no se
    // pide nada y tampoco cuenta como una denegación.
    final current = await _permissionService.checkMicrophone();
    if (!mounted) return;
    if (current == AppPermissionStatus.denied) {
      final accepted = await _confirmMicRationale();
      if (!accepted || !mounted) return;
    }

    _requestingMic = true;
    try {
      await _recorderService.start();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _micBlockedStatus = null;
      });
    } on RecorderException catch (e) {
      if (!mounted) return;
      final status = e.permissionStatus;
      setState(() {
        if (status != null) {
          // Problema de permiso: la UI muestra el aviso del estado.
          _micBlockedStatus = status;
        } else {
          _audioStatusMessage = 'No se pudo iniciar la grabación: $e';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioStatusMessage = 'No se pudo iniciar la grabación: $e');
    } finally {
      _requestingMic = false;
    }
  }

  void _openSubmissions() {
    final room = _findRoom(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubmissionsScreen(
          roomId: widget.roomId,
          roomName: room?.name ?? 'Sala',
        ),
      ),
    );
  }

  Future<void> _stopAndSend() async {
    setState(() => _isRecording = false);

    final RecordedAudio? recording;
    try {
      recording = await _recorderService.stop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioStatusMessage = 'No se pudo detener la grabación: $e');
      return;
    }
    if (!mounted) return;

    if (recording == null) {
      setState(() => _audioStatusMessage = 'No se grabó ningún audio.');
      return;
    }

    // Un audio vacío, demasiado corto o sin sonido no se envía: llegaría
    // al backend como un archivo que "suena" a nada.
    final problem = recording.problem;
    if (problem != null) {
      setState(() => _audioStatusMessage = problem);
      return;
    }

    setState(() {
      _isUploading = true;
      _audioStatusMessage = 'Enviando audio al backend...';
    });

    try {
      final response =
          await _roomsService.processAudio(
        widget.roomId,
        recording.file,
        durationSeconds: recording.duration.inSeconds,
      );
      final taskId = response['task_id'] as String?;
      final queueFailed = response['processing_status'] == 'FAILURE';
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _audioStatusMessage = null;
        _audioSent = true;
      });
      // El procesamiento sigue en segundo plano: se consulta sin mostrar
      // estados intermedios al usuario (solo se avisa si falla).
      if (!queueFailed && taskId != null) unawaited(_pollTaskStatus(taskId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _audioStatusMessage = e is NetworkException
            ? 'No se pudo enviar el audio: ${e.message}'
            : 'Error al enviar el audio: $e';
      });
    }
  }

  /// Consulta el estado de la tarea de Celery hasta que termine. Cada
  /// consulta también sincroniza el resultado hacia la base de datos (ver
  /// `GET /tasks/<id>` en el backend). No muestra nada si todo va bien;
  /// solo avisa si el procesamiento falla.
  Future<void> _pollTaskStatus(String taskId) async {
    const maxAttempts = 10;
    const interval = Duration(seconds: 2);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(interval);
      if (!mounted) return;

      try {
        final status = await _roomsService.getTaskStatus(taskId);
        final state = status['state'] as String?;
        if (!mounted) return;

        if (state == 'SUCCESS') return;
        if (state == 'FAILURE') {
          // El audio SÍ quedó guardado: el fallo del procesamiento en
          // segundo plano no se muestra al usuario.
          return;
        }
      } catch (_) {
        // Un fallo de red al consultar no invalida el envío: se reintenta.
      }
    }
  }

  /// Aviso del micrófono según el estado del permiso. Sin bloqueo no
  /// muestra nada.
  Widget _buildMicNotice() {
    final status = _micBlockedStatus;
    if (status == null) return const SizedBox.shrink();

    switch (status) {
      case AppPermissionStatus.denied:
        return PermissionNotice(
          icon: Icons.mic_off,
          message: 'Sin el micrófono no podemos grabar tu práctica de '
              'speaking. Puedes permitirlo cuando quieras.',
          actionLabel: 'Permitir micrófono',
          actionIcon: Icons.mic,
          onAction: _retryMicPermission,
        );
      case AppPermissionStatus.permanentlyDenied:
        return PermissionNotice(
          icon: Icons.mic_off,
          message: 'Denegaste el micrófono de forma permanente. Actívalo '
              'desde los ajustes de la app para poder grabar.',
          actionLabel: 'Abrir Ajustes',
          actionIcon: Icons.settings,
          onAction: _openAppSettings,
        );
      case AppPermissionStatus.restricted:
        return const PermissionNotice(
          icon: Icons.mic_off,
          message: 'El micrófono no está disponible en este dispositivo '
              '(puede estar restringido por el sistema), así que no se '
              'puede grabar.',
        );
      case AppPermissionStatus.granted:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAudioSection({bool roomPending = false}) {
    // Si el micrófono está bloqueado, "Grabar" se deshabilita. Mientras
    // se graba siempre se puede detener.
    final micBlocked = _micBlockedStatus != null && !_isRecording;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Práctica de audio', style: AppTokens.textTitle),
          const SizedBox(height: AppTokens.spaceMD),
          AppButton(
            label: _isRecording ? 'Detener y enviar' : 'Grabar',
            icon: _isRecording ? Icons.stop : Icons.mic,
            loading: _isUploading,
            onPressed: (micBlocked || roomPending)
                ? null
                : (_isRecording ? _stopAndSend : _startRecording),
            variant: _isRecording
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
          ),
          if (roomPending) ...[
            const SizedBox(height: AppTokens.spaceMD),
            Text(
              'Esta sala aún no se ha sincronizado con el servidor. '
              'Cuando haya conexión podrás grabar y ver el historial.',
              style: AppTokens.textCaption,
            ),
          ],
          if (micBlocked) ...[
            const SizedBox(height: AppTokens.spaceMD),
            _buildMicNotice(),
          ],
          if (_audioStatusMessage != null) ...[
            const SizedBox(height: AppTokens.spaceMD),
            Text(_audioStatusMessage!, style: AppTokens.textBody),
          ],
          const SizedBox(height: AppTokens.spaceSM),
          AppButton(
            label: 'Ver historial de envíos',
            icon: Icons.history,
            variant: AppButtonVariant.secondary,
            onPressed: roomPending ? null : _openSubmissions,
          ),
          if (_audioSent) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.spaceSM),
              decoration: BoxDecoration(
                color: AppTokens.colorSuccessContainer,
                borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              ),
              child: const Text(
                'Audio guardado correctamente. Puedes verlo en el historial.',
                style: TextStyle(color: AppTokens.colorOnSuccessContainer),
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
    final room = _findRoom(context, listen: true);
    final isHost = room != null && room.hostId == currentUser?.id;
    final roomsLoading = context.watch<RoomsProvider>().isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(room?.name ?? 'Sala')),
      body: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMD),
        child: StatusView(
          loading: roomsLoading && room == null,
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
                _buildAudioSection(roomPending: room.id < 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
