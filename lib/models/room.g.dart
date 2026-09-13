// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoomHost _$RoomHostFromJson(Map<String, dynamic> json) => RoomHost(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
    );

Map<String, dynamic> _$RoomHostToJson(RoomHost instance) => <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
    };

Room _$RoomFromJson(Map<String, dynamic> json) => Room(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      active: json['active'] as bool,
      host: json['host'] == null
          ? null
          : RoomHost.fromJson(json['host'] as Map<String, dynamic>),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$RoomToJson(Room instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'active': instance.active,
      'host': instance.host?.toJson(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
