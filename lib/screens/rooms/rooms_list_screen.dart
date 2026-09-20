import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/tokens.dart';
import '../../models/user_location.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../state/auth_provider.dart';
import '../../state/rooms_provider.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/permission_ui.dart';
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
///
/// Taller Semana 14 (Fase 3): sección OPCIONAL "Salas cerca de ti"
/// (capacidad de ubicación). El permiso se pide solo cuando el usuario
/// pulsa "Ver salas cercanas" (nunca al abrir la pantalla), precedido
/// de una explicación. Al abrir solo se COMPRUEBA el estado. Cada
/// estado tiene su propio aviso; ninguno bloquea el resto de la pantalla
/// (crear sala, lista, pull-to-refresh):
/// - *denied*: aviso + botón para pedir de nuevo (con la explicación).
/// - *permanentlyDenied*: aviso + "Abrir Ajustes".
/// - *servicio de ubicación apagado*: aviso distinto (el permiso SÍ está
///   concedido, es el GPS del sistema) + botón a los ajustes de ubicación.
/// - *restricted*: aviso informativo.
/// Al volver de Ajustes se re-comprueba solo, sin reiniciar la app.
///
/// Fase 4: al obtener la posición se entrega (redondeada, ver
/// `UserLocation`) al `RoomsProvider`, que la guarda en la caché local y
/// la envía al backend con el listado. Si el permiso deja de estar
/// concedido se entrega `null` ("sin ubicación"), lo que borra las
/// coordenadas guardadas: sin permiso no se conserva ni se envía nada.
class RoomsListScreen extends StatefulWidget {
  const RoomsListScreen({super.key});

  @override
  State<RoomsListScreen> createState() => _RoomsListScreenState();
}

/// Estados de la sección "Salas cerca de ti".
enum _NearbyState {
  /// Aún no se ha pedido nada: se muestra la invitación (opt-in).
  idle,
  loading,

  /// Permiso concedido, GPS encendido y posición obtenida.
  ready,

  /// El usuario denegó el permiso (se puede volver a pedir).
  denied,

  /// Denegado permanentemente: solo se arregla desde Ajustes.
  permanentlyDenied,

  /// Permiso no disponible en este dispositivo (restricción del sistema).
  restricted,

  /// Permiso concedido pero el GPS del dispositivo está apagado.
  serviceOff,

  /// Falló la obtención de la posición por otra causa (ej. timeout).
  error,
}

class _RoomsListScreenState extends State<RoomsListScreen>
    with WidgetsBindingObserver {
  final _permissionService = PermissionService();
  late final LocationService _locationService =
      LocationService(permissionService: _permissionService);

  _NearbyState _nearbyState = _NearbyState.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomsProvider>().refresh();
    });
    // Solo COMPRUEBA el estado (no muestra ningún diálogo del sistema).
    _evaluateNearby();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de Ajustes (permisos de la app o ubicación del sistema)
  /// se re-comprueba, para que la sección se actualice sin reiniciar la
  /// app. Solo en los estados que dependen de algo que se arregla fuera
  /// de la app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    const fixableOutside = {
      _NearbyState.denied,
      _NearbyState.permanentlyDenied,
      _NearbyState.restricted,
      _NearbyState.serviceOff,
    };
    if (fixableOutside.contains(_nearbyState)) _evaluateNearby();
  }

  /// Lee el estado del permiso SIN solicitarlo y ajusta la sección.
  Future<void> _evaluateNearby() async {
    if (_nearbyState == _NearbyState.loading) return;
    final status = await _permissionService.checkLocation();
    if (!mounted) return;

    switch (status) {
      case AppPermissionStatus.granted:
        // Ya concedido: no hay diálogo del sistema; se carga directo (y
        // si el GPS está apagado, `_loadNearby` lo distingue).
        await _loadNearby();
      case AppPermissionStatus.permanentlyDenied:
        await _forgetLocation();
        if (!mounted) return;
        setState(() => _nearbyState = _NearbyState.permanentlyDenied);
      case AppPermissionStatus.restricted:
        await _forgetLocation();
        if (!mounted) return;
        setState(() => _nearbyState = _NearbyState.restricted);
      case AppPermissionStatus.denied:
        await _forgetLocation();
        if (!mounted) return;
        // En Android "nunca pedido" y "denegado una vez" llegan igual:
        // si el usuario ya lo denegó aquí se conserva el aviso; si no, se
        // muestra la invitación.
        if (_nearbyState != _NearbyState.denied) {
          setState(() => _nearbyState = _NearbyState.idle);
        }
    }
  }

  /// Fase 4: sin permiso concedido no se conserva ni se envía ninguna
  /// posición. Guarda el estado "sin ubicación" (borra las coordenadas
  /// anteriores de la caché local).
  Future<void> _forgetLocation() =>
      context.read<RoomsProvider>().updateLocation(null);

  /// Explica para qué se usa la ubicación y, si el usuario acepta, pide
  /// el permiso. Con "Ahora no" no se pide nada ni cuenta como denegación.
  Future<void> _requestNearby() async {
    final accepted = await showPermissionRationaleDialog(
      context,
      title: 'Ubicación para salas cercanas',
      message: 'Usamos tu ubicación aproximada para mostrarte salas de '
          'práctica cercanas mientras usas la app. Es opcional: si '
          'prefieres no compartirla, todo lo demás sigue funcionando igual.',
    );
    if (!accepted || !mounted) return;
    await _loadNearby();
  }

  /// Pide el permiso si hace falta (vía `LocationService`, que usa el
  /// `PermissionService`) y obtiene la posición. Cada excepción se
  /// traduce a un estado distinto de la UI.
  ///
  /// Fase 4: con posición obtenida, se entrega al provider (caché local
  /// + envío al backend). Con permiso no concedido se entrega `null`.
  /// Con GPS apagado o un error transitorio NO se toca la última
  /// ubicación guardada: el permiso sigue vigente, solo falta un fix.
  Future<void> _loadNearby() async {
    // Se toma antes de cualquier await: el provider es global y sigue
    // vivo aunque esta pantalla se cierre a mitad de la operación.
    final roomsProvider = context.read<RoomsProvider>();
    setState(() => _nearbyState = _NearbyState.loading);

    final UserLocation location;
    try {
      final position = await _locationService.getCurrentPosition();
      location = UserLocation.approximate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on LocationServiceDisabledException {
      if (!mounted) return;
      setState(() => _nearbyState = _NearbyState.serviceOff);
      return;
    } on LocationPermissionException catch (e) {
      await roomsProvider.updateLocation(null);
      if (!mounted) return;
      setState(() {
        _nearbyState = switch (e.status) {
          AppPermissionStatus.permanentlyDenied =>
            _NearbyState.permanentlyDenied,
          AppPermissionStatus.restricted => _NearbyState.restricted,
          AppPermissionStatus.denied ||
          AppPermissionStatus.granted =>
            _NearbyState.denied,
        };
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyState = _NearbyState.error);
      return;
    }

    if (mounted) setState(() => _nearbyState = _NearbyState.ready);
    // Guarda en la caché local y, si cambió, refresca la lista enviando
    // la ubicación al backend.
    await roomsProvider.updateLocation(location);
  }

  Future<void> _openAppSettings() => _permissionService.openSettings();

  Future<void> _openLocationSettings() =>
      _locationService.openLocationSettings();

  /// Sección "Salas cerca de ti". Nunca bloquea el resto de la pantalla:
  /// sin ubicación solo se ve el aviso del estado, sin la lista.
  Widget _buildNearbySection(RoomsProvider rooms) {
    switch (_nearbyState) {
      case _NearbyState.idle:
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Salas cerca de ti', style: AppTokens.textBodyLarge),
              const SizedBox(height: AppTokens.spaceXS),
              Text(
                'Descubre salas de práctica cercanas. Es opcional.',
                style: AppTokens.textCaption,
              ),
              const SizedBox(height: AppTokens.spaceSM),
              AppButton(
                label: 'Ver salas cercanas',
                icon: Icons.near_me,
                variant: AppButtonVariant.secondary,
                onPressed: _requestNearby,
              ),
            ],
          ),
        );
      case _NearbyState.loading:
        return const AppCard(
          child: Row(
            children: [
              SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: AppTokens.spaceSM),
              Expanded(
                child: Text('Buscando salas cerca de ti...',
                    style: AppTokens.textBody),
              ),
            ],
          ),
        );
      case _NearbyState.ready:
        return _buildNearbyReady(rooms);
      case _NearbyState.denied:
        return PermissionNotice(
          icon: Icons.location_off,
          message: 'Sin tu ubicación no podemos sugerirte salas cercanas. '
              'El resto de la app sigue funcionando igual.',
          actionLabel: 'Permitir ubicación',
          actionIcon: Icons.location_on,
          onAction: _requestNearby,
        );
      case _NearbyState.permanentlyDenied:
        return PermissionNotice(
          icon: Icons.location_off,
          message: 'Denegaste el permiso de ubicación de forma permanente. '
              'Actívalo desde los ajustes de la app para ver salas cercanas.',
          actionLabel: 'Abrir Ajustes',
          actionIcon: Icons.settings,
          onAction: _openAppSettings,
        );
      case _NearbyState.restricted:
        return const PermissionNotice(
          icon: Icons.location_off,
          message: 'La ubicación no está disponible en este dispositivo '
              '(puede estar restringida por el sistema), así que no podemos '
              'sugerirte salas cercanas.',
        );
      case _NearbyState.serviceOff:
        // Mensaje DISTINTO al de permiso denegado: aquí el permiso sí
        // está concedido, lo que está apagado es el GPS del dispositivo.
        return PermissionNotice(
          icon: Icons.gps_off,
          message: 'La app tiene permiso de ubicación, pero la ubicación '
              'del dispositivo está apagada. Enciéndela para ver salas '
              'cercanas.',
          actionLabel: 'Abrir ajustes de ubicación',
          actionIcon: Icons.settings,
          onAction: _openLocationSettings,
        );
      case _NearbyState.error:
        return PermissionNotice(
          icon: Icons.error_outline,
          message: 'No pudimos obtener tu ubicación en este momento. '
              'Puedes intentarlo de nuevo.',
          actionLabel: 'Reintentar',
          actionIcon: Icons.refresh,
          onAction: _loadNearby,
        );
    }
  }

  /// Contenido cuando ya hay posición. Las salas no guardan ubicación
  /// todavía, así que por ahora se sugieren las salas activas. La
  /// ubicación aproximada ya llega al backend (Fase 4); el orden por
  /// distancia real requiere que las salas incluyan sus coordenadas.
  Widget _buildNearbyReady(RoomsProvider rooms) {
    final suggested = rooms.rooms.where((r) => r.active).take(3).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on,
                  size: 18, color: AppTokens.colorPrimary),
              const SizedBox(width: AppTokens.spaceXS),
              Text('Salas cerca de ti', style: AppTokens.textBodyLarge),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSM),
          if (suggested.isEmpty)
            Text('Todavía no hay salas activas para sugerirte.',
                style: AppTokens.textBody)
          else
            Wrap(
              spacing: AppTokens.spaceSM,
              runSpacing: AppTokens.spaceSM,
              children: [
                for (final room in suggested)
                  ActionChip(
                    avatar: const Icon(Icons.meeting_room, size: 18),
                    label: Text(room.name),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RoomDetailScreen(roomId: room.id),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppTokens.spaceSM),
          Text(
            'Ubicación aproximada detectada. Por ahora sugerimos las salas '
            'activas; el orden por distancia llegará cuando las salas '
            'incluyan su ubicación.',
            style: AppTokens.textCaption,
          ),
        ],
      ),
    );
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

    if (name != null) {
      setState(() => _creating = true);
      await provider.create(
        name,
        hostId: currentUser?.id,
        hostUsername: currentUser?.username,
      );
      if (mounted) setState(() => _creating = false);

      final syncError = provider.consumeLastSyncError();
      if (syncError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(syncError)),
        );
      }
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
            _buildNearbySection(rooms),
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
