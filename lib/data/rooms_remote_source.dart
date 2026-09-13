import 'dart:convert';
import 'dart:io';

import '../models/room.dart';
import '../services/api_service.dart';

/// Excepción con el mensaje de error tal cual lo devuelve el backend
/// (clave `error` del JSON), para mostrarlo directo en la UI.
class RoomException implements Exception {
  const RoomException(this.message);
  final String message;

  @override
  String toString() => message;
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
  Future<List<Room>> listRooms({bool optimized = true}) async {
    final response = await _apiService.get(
      '/rooms/list',
      queryParameters: {'optimized': optimized.toString()},
    );

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rooms = data['rooms'] as List<dynamic>;
    return rooms.map((r) => Room.fromJson(r as Map<String, dynamic>)).toList();
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
  Future<Room> createRoom(String name) async {
    final response = await _apiService.authorizedPost('/rooms', body: {'name': name});

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
