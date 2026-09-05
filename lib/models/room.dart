/// Modelo de sala (room).
///
/// Coincide con lo que devuelve el backend en `GET /rooms/list`,
/// `GET /rooms/<id>` y `POST /rooms`, donde el host llega anidado
/// como `host: {id, username}`.
///
/// Taller Semana 12: agrega `updatedAt` (necesario para la estrategia de
/// conflictos) y helpers de (de)serialización hacia la caché SQLite
/// local (`toCacheMap`/`fromCacheMap`), separados de `fromJson` (que
/// habla el formato del backend) para no mezclar los dos contratos.
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.active,
    required this.hostId,
    required this.hostUsername,
    required this.updatedAt,
    this.pendingSync = false,
  });

  final int id;
  final String name;
  final bool active;
  final int? hostId;
  final String? hostUsername;
  final DateTime updatedAt;

  /// true si esta sala tiene una operación local todavía no confirmada
  /// por el servidor (creación o edición en la cola). Es un dato de solo
  /// UI, calculado por el provider — no viene del backend ni se guarda
  /// en la caché.
  final bool pendingSync;

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
      hostId: hostId,
      hostUsername: hostUsername,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  factory Room.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as Map<String, dynamic>?;
    return Room(
      id: json['id'] as int,
      name: json['name'] as String,
      active: json['active'] as bool,
      hostId: host?['id'] as int?,
      hostUsername: host?['username'] as String?,
      // El backend siempre manda `updated_at`; si algún día faltara
      // (respuesta vieja en caché), caemos a "ahora" para no romper el
      // parseo.
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// Fila para la tabla `rooms_cache` de SQLite (ver `local_db_service.dart`).
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
    return Room(
      id: map['id'] as int,
      name: map['name'] as String,
      active: (map['active'] as int) == 1,
      hostId: map['host_id'] as int?,
      hostUsername: map['host_username'] as String?,
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
