import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

/// Modelo de usuario.
///
/// Coincide con lo que devuelve el backend en `GET /auth/me`, que
/// responde `{"user": {"id": ..., "username": ..., "email": ...}}`.
///
/// Taller Semana 13 (Bloque 5): serialización generada con
/// `json_serializable` (`_$UserFromJson`/`_$UserToJson` en
/// `user.g.dart`). Sin divergencias de nomenclatura que documentar: los
/// tres campos coinciden 1:1 entre servidor y cliente.
@JsonSerializable()
class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
  });

  final int id;
  final String username;
  final String email;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
