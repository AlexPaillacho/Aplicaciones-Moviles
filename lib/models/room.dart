/// Modelo de sala (room).
///
/// Coincide con lo que devuelve el backend en `GET /rooms/list`,
/// `GET /rooms/<id>` y `POST /rooms`, donde el host llega anidado
/// como `host: {id, username}`.
class Room {
  const Room({
    required this.id,
    required this.name,
    required this.active,
    required this.hostId,
    required this.hostUsername,
  });

  final int id;
  final String name;
  final bool active;
  final int? hostId;
  final String? hostUsername;

  factory Room.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as Map<String, dynamic>?;
    return Room(
      id: json['id'] as int,
      name: json['name'] as String,
      active: json['active'] as bool,
      hostId: host?['id'] as int?,
      hostUsername: host?['username'] as String?,
    );
  }
}
