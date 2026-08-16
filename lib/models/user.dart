/// Modelo de usuario.
///
/// Coincide con lo que devuelve el backend en `GET /auth/me`, que
/// responde `{"user": {"id": ..., "username": ..., "email": ...}}`.
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
  });

  final int id;
  final String username;
  final String email;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
    );
  }
}
