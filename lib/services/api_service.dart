import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'token_storage.dart';

/// Excepción lanzada cuando el backend responde 401.
///
/// Se maneja de forma centralizada en la Fase 5 (logout automático).
/// Por ahora, cada pantalla que la reciba puede mostrarla como error.
class UnauthorizedException implements Exception {
  const UnauthorizedException([this.message = 'No autorizado']);
  final String message;

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Único punto de configuración de la URL base del backend.
///
/// Ninguna pantalla debe hacer `http.get`/`http.post` directo: todo pasa
/// por aquí (o por los servicios que lo envuelven, como `auth_service.dart`
/// y `rooms_service.dart`).
class ApiService {
  ApiService({
    this.baseUrl = AppConstants.apiBaseUrl,
    http.Client? client,
    TokenStorage? tokenStorage,
  })  : _client = client ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorage();

  final String baseUrl;
  final http.Client _client;
  final TokenStorage _tokenStorage;

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  /// GET público (sin token), ej. `GET /rooms/list`.
  Future<http.Response> get(String path, {Map<String, String>? queryParameters}) {
    return _client.get(_buildUri(path, queryParameters));
  }

  /// POST público (sin token), ej. `POST /auth/login`.
  Future<http.Response> post(String path, {Map<String, dynamic>? body}) {
    return _client.post(
      _buildUri(path),
      headers: _jsonHeaders,
      body: body != null ? jsonEncode(body) : null,
    );
  }

  /// GET autenticado. Agrega `Authorization: Bearer <token>` leyendo el
  /// token desde `TokenStorage`. Si el backend responde 401, lanza
  /// `UnauthorizedException`.
  Future<http.Response> authorizedGet(String path, {Map<String, String>? queryParameters}) async {
    final token = await _tokenStorage.readToken();
    final response = await _client.get(
      _buildUri(path, queryParameters),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    return response;
  }

  /// POST autenticado. Agrega `Authorization: Bearer <token>` leyendo el
  /// token desde `TokenStorage`. Si el backend responde 401, lanza
  /// `UnauthorizedException`.
  Future<http.Response> authorizedPost(String path, {Map<String, dynamic>? body}) async {
    final token = await _tokenStorage.readToken();
    final response = await _client.post(
      _buildUri(path),
      headers: {
        ..._jsonHeaders,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    return response;
  }

  /// PUT autenticado. Igual que `authorizedPost` pero con método PUT
  /// (se necesita en la Fase 3 para `PUT /rooms/<id>`).
  Future<http.Response> authorizedPut(String path, {Map<String, dynamic>? body}) async {
    final token = await _tokenStorage.readToken();
    final response = await _client.put(
      _buildUri(path),
      headers: {
        ..._jsonHeaders,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body != null ? jsonEncode(body) : null,
    );
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    return response;
  }

  /// DELETE autenticado (se necesita en la Fase 3 para `DELETE /rooms/<id>`).
  Future<http.Response> authorizedDelete(String path) async {
    final token = await _tokenStorage.readToken();
    final response = await _client.delete(
      _buildUri(path),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    return response;
  }

  /// POST multipart autenticado (se necesita en la Fase 4 para enviar el
  /// audio grabado a `POST /rooms/<id>/process-audio`, campo `audio`).
  Future<http.Response> authorizedMultipartPost(
    String path, {
    required String fileField,
    required File file,
  }) async {
    final token = await _tokenStorage.readToken();
    final request = http.MultipartRequest('POST', _buildUri(path))
      ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'})
      ..files.add(await http.MultipartFile.fromPath(fileField, file.path));

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 401) {
      throw const UnauthorizedException();
    }
    return response;
  }
}
