import 'package:json_annotation/json_annotation.dart';

part 'room.g.dart';

/// Host anidado tal como lo entrega el backend: `host: {id, username}`.
///
/// Taller Semana 13 (Bloque 5): entidad propia con serialización
/// generada, para poder documentar la divergencia servidor↔cliente
/// (ver comentario en `Room`) sin ensuciar el `fromJson` a mano.
@JsonSerializable()
class RoomHost {
  const RoomHost({required this.id, required this.username});

  final int id;
  final String username;

  factory RoomHost.fromJson(Map<String, dynamic> json) => _$RoomHostFromJson(json);
  Map<String, dynamic> toJson() => _$RoomHostToJson(this);
}

/// Modelo de sala (room).
///
/// Coincide con lo que devuelve el backend en `GET /rooms/list`,
/// `GET /rooms/<id>` y `POST /rooms`.
///
/// Taller Semana 13 (Bloque 5): serialización generada con
/// `json_serializable` (`_$RoomFromJson`/`_$RoomToJson` en
/// `room.g.dart`, generado con `dart run build_runner build`).
///
/// **Divergencia de nomenclatura servidor↔cliente documentada:** el
/// backend entrega el host como objeto anidado (`host: {id, username}`),
/// pero el resto de la app (pantallas, caché SQLite de Semana 12) ya
/// usaba los campos planos `hostId`/`hostUsername`. En vez de tocar
/// todos esos call sites, `host` se deserializa tal cual (anidado) y
/// `hostId`/`hostUsername` quedan como *getters* derivados — no son
/// campos del JSON ni de la serialización generada.
@JsonSerializable(explicitToJson: true)
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.active,
    this.host,
    required this.updatedAt,
    this.pendingSync = false,
  });

  final int id;
  final String name;
  final bool active;

  /// Host anidado tal como lo manda el backend. `null` es válido y
  /// esperado (campo opcional anulable, ver Bloque 5): una sala puede
  /// no tener host resuelto en la respuesta.
  final RoomHost? host;

  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// true si esta sala tiene una operación local todavía no confirmada
  /// por el servidor (creación o edición en la cola). Es un dato de solo
  /// UI, calculado por el provider — no viene del backend ni se guarda
  /// en la caché, así que se excluye de la (de)serialización generada.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool pendingSync;

  /// Getters derivados de `host` (ver nota de divergencia arriba). El
  /// resto de la app sigue leyendo `room.hostId` / `room.hostUsername`
  /// sin enterarse de que el backend los anida.
  int? get hostId => host?.id;
  String? get hostUsername => host?.username;

  Room copyWith({
    String? name,
    bool? active,
    DateTime? updatedAt,
    bool? pendingSync,
  }) {
    return Room(
      id: id,
      name: name ?? this.name,
      active: active ?? this.active,
      host: host,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
  Map<String, dynamic> toJson() => _$RoomToJson(this);

  /// Fila para la tabla `rooms_cache` de SQLite (ver `rooms_local_source.dart`).
  /// No es el contrato del backend, así que se mantiene manual en vez de
  /// generado: aplana `host` en dos columnas (`host_id`, `host_username`).
  Map<String, Object?> toCacheMap() {
    return {
      'id': id,
      'name': name,
      'active': active ? 1 : 0,
      'host_id': hostId,
      'host_username': hostUsername,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Room.fromCacheMap(Map<String, Object?> map) {
    final cachedHostId = map['host_id'] as int?;
    final cachedHostUsername = map['host_username'] as String?;
    return Room(
      id: map['id'] as int,
      name: map['name'] as String,
      active: (map['active'] as int) == 1,
      host: (cachedHostId != null && cachedHostUsername != null)
          ? RoomHost(id: cachedHostId, username: cachedHostUsername)
          : null,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
