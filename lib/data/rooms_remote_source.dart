import 'dart:convert';
import 'dart:io';

import '../models/room.dart';
import '../models/user_location.dart';
import '../services/api_service.dart';

/// Excepción con el mensaje de error tal cual lo devuelve el backend
/// (clave `error` del JSON), para mostrarlo directo en la UI.
class RoomException implements Exception {
  const RoomException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Resultado de `GET /rooms/list` con metadatos de paginación (Fase 1
/// del Plan de fases pendientes): además de las salas de esta página,
/// trae lo necesario para saber si hay una página siguiente
/// (`page < totalPages`).
class RoomsPage {
  const RoomsPage({
    required this.rooms,
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  final List<Room> rooms;
  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Se lanza cuando `PUT /rooms/<id>` responde 409: la sala cambió en el
/// servidor mientras la edición estaba encolada offline. Trae la versión
/// vigente del servidor para que quien la capture (`RoomsRepository`)
/// descarte la edición local y realinee la caché.
class RoomConflictException implements Exception {
  const RoomConflictException(this.serverRoom);
  final Room serverRoom;

  @override
  String toString() => 'Conflicto: la sala cambió en el servidor';
}

/// Fuente de datos remota de salas (rooms) contra el backend Flask.
///
/// Taller Semana 13 (Bloque 6): esta clase es la capa "remoto" de la
/// nueva arquitectura de datos (remoto / local / repositorio). Antes de
/// este bloque se llamaba `RoomsService` y mezclaba, sin quererlo, la
/// responsabilidad de hablar HTTP con la de decidir cuándo leer/escribir
/// caché o encolar offline; ahora solo sabe hablar con el backend — no
/// conoce `RoomsLocalSource` ni la cola offline. Esa orquestación vive en
/// `RoomsRepository`.
class RoomsRemoteSource {
  RoomsRemoteSource(this._apiService);

  final ApiService _apiService;

  /// `GET /rooms/list?optimized=...` (público, sin JWT).
  ///
  /// Taller Semana 14 (Fase 4): si [location] no es `null`, se agregan
  /// `lat` y `lng` a la consulta para que el backend pueda, a futuro,
  /// ordenar por cercanía. Sin ubicación la petición es idéntica a la de
  /// antes: el parámetro es opcional y la lista funciona igual.
  Future<List<Room>> listRooms({
    bool optimized = true,
    UserLocation? location,
  }) async {
    return (await listRoomsPage(optimized: optimized, location: location)).rooms;
  }

  /// `GET /rooms/list?page=..&per_page=..` (público, sin JWT).
  ///
  /// Fase 1 (Plan de fases pendientes): igual que [listRooms], pero
  /// devuelve además los metadatos de paginación (`total`,
  /// `totalPages`) que el backend calcula, para que `RoomsRepository`
  /// sepa si hay una página siguiente que pedir ("cargar más").
  Future<RoomsPage> listRoomsPage({
    bool optimized = true,
    UserLocation? location,
    int page = 1,
    int perPage = 10,
  }) async {
    final query = <String, String>{
      'optimized': optimized.toString(),
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (location != null) {
      query['lat'] = location.latitude.toString();
      query['lng'] = location.longitude.toString();
    }

    final response = await _apiService.get(
      '/rooms/list',
      queryParameters: query,
    );

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rooms = (data['rooms'] as List<dynamic>)
        .map((r) => Room.fromJson(r as Map<String, dynamic>))
        .toList();

    // El backend siempre manda page/per_page/total/total_pages desde la
    // Fase 1, pero se leen con valores por defecto tolerantes por si
    // alguna vez se apunta contra una versión vieja del backend.
    return RoomsPage(
      rooms: rooms,
      page: data['page'] as int? ?? page,
      perPage: data['per_page'] as int? ?? perPage,
      total: data['total'] as int? ?? rooms.length,
      totalPages: data['total_pages'] as int? ?? 1,
    );
  }

  /// `GET /rooms/<id>` (público).
  Future<Room> getRoom(int id) async {
    final response = await _apiService.get('/rooms/$id');

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Room.fromJson(data['room'] as Map<String, dynamic>);
  }

  /// `POST /rooms` (JWT, usa `authorizedPost`).
  ///
  /// Taller Semana 14 (Fase 4): si [location] no es `null`, se envía
  /// como `latitude`/`longitude` en el cuerpo (ubicación aproximada del
  /// usuario al crear la sala). Sin ubicación el cuerpo es solo `name`,
  /// igual que antes.
  Future<Room> createRoom(String name, {UserLocation? location}) async {
    final body = <String, dynamic>{'name': name};
    if (location != null) {
      body['latitude'] = location.latitude;
      body['longitude'] = location.longitude;
    }
    final response = await _apiService.authorizedPost('/rooms', body: body);

    if (response.statusCode != 201) {
      throw RoomException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Room.fromJson(data['room'] as Map<String, dynamic>);
  }

  /// `PUT /rooms/<id>` (JWT).
  ///
  /// `expectedUpdatedAt` es el `updated_at` que el cliente tenía en su
  /// caché al momento de encolar esta edición (offline-first: se guarda
  /// junto a la operación pendiente y se reenvía recién al sincronizar,
  /// ver `RoomsRepository`). Si el servidor responde 409 (la sala cambió
  /// mientras tanto), se lanza [RoomConflictException] con la versión
  /// vigente del servidor en vez de [RoomException], para que el
  /// llamador pueda distinguir "falló" de "hay que resolver un
  /// conflicto".
  Future<Room> updateRoom(
    int id, {
    String? name,
    bool? active,
    String? expectedUpdatedAt,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'active': ?active,
      'expected_updated_at': ?expectedUpdatedAt,
    };
    final response = await _apiService.authorizedPut('/rooms/$id', body: body);

    if (response.statusCode == 409) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverRoom = Room.fromJson(data['room'] as Map<String, dynamic>);
      throw RoomConflictException(serverRoom);
    }

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Room.fromJson(data['room'] as Map<String, dynamic>);
  }

  /// `DELETE /rooms/<id>` (JWT).
  Future<void> deleteRoom(int id) async {
    final response = await _apiService.authorizedDelete('/rooms/$id');

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }
  }

  /// `POST /rooms/<id>/process-audio` (JWT, multipart, campo `audio`).
  /// Responde 202 con `{message, task_id, saved_file}`.
  Future<Map<String, dynamic>> processAudio(int roomId, File audioFile) async {
    final response = await _apiService.authorizedMultipartPost(
      '/rooms/$roomId/process-audio',
      fileField: 'audio',
      file: audioFile,
    );

    if (response.statusCode != 202) {
      throw RoomException(_extractError(response.body));
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// `GET /tasks/<task_id>` (JWT). Responde `{task_id, state, result?, error?}`.
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    final response = await _apiService.authorizedGet('/tasks/$taskId');

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _extractError(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      return data['error'] as String? ?? 'Error desconocido';
    } catch (_) {
      return 'Error desconocido';
    }
  }
}
