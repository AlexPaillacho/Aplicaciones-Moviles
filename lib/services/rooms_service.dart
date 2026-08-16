import 'dart:convert';
import 'dart:io';

import '../models/room.dart';
import 'api_service.dart';

/// Excepción con el mensaje de error tal cual lo devuelve el backend
/// (clave `error` del JSON), para mostrarlo directo en la UI.
class RoomException implements Exception {
  const RoomException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Servicio de salas (rooms) contra el backend Flask.
///
/// Se completa aquí en la Fase 3 (listar/crear/editar/eliminar salas).
/// La Fase 4 agrega `processAudio` y `getTaskStatus`.
class RoomsService {
  RoomsService(this._apiService);

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
  Future<void> updateRoom(int id, {String? name, bool? active}) async {
    final body = <String, dynamic>{
      'name': ?name,
      'active': ?active,
    };
    final response = await _apiService.authorizedPut('/rooms/$id', body: body);

    if (response.statusCode != 200) {
      throw RoomException(_extractError(response.body));
    }
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
