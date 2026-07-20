import json

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from sqlalchemy.orm import joinedload

from app import db
from app.cache import redis_client
from app.models import Room
from app.tasks import process_audio_session

from app.auth.routes import jwt_user_required

# Endpoint POST /rooms/<room_id>/process-audio:
# Ejecuta la tarea pesada en segundo plano (Celery) y retorna 202 con el task_id.

rooms_bp = Blueprint('rooms', __name__)

CACHE_TTL = 300  # Tiempo de vida de la caché: 5 minutos (300 segundos)


def _cache_key(room_id: str) -> str:
    return f"rooms:{room_id}"


def _room_to_dict(room: Room) -> dict:
    # Convertimos el modelo SQLAlchemy a un dict JSON-friendly.
    # Nota: para demostrar N+1, el campo host.username se accede desde `room.host`.
    host = room.host
    return {
        'id': room.id,
        'name': room.name,
        'active': room.active,
        'host': {
            'id': host.id if host else None,
            'username': host.username if host else None,
        },
    }


# ===== Estrategia Cache-Aside e Invalidación =====

# GET lista de salas
# Para la corrección de N+1 usamos eager loading (joinedload) sobre la relación `host`.
# Técnicamente: `joinedload(Room.host)` hace un JOIN explícito en la consulta principal,
# evitando que al iterar sobre rooms se ejecuten consultas adicionales por cada room.


# Nota: GET /rooms/list se deja público (sin JWT).
# Para la demo del video, el objetivo es comparar N+1 (lazy loading) vs eager loading (joinedload)
# sin que la autenticación afecte el número de queries en la ruta.
@rooms_bp.route('/rooms/list', methods=['GET'])
def list_rooms():
    try:
        optimized = request.args.get('optimized', 'false').lower() == 'true'

        if optimized:
            # Versión CORREGIDA (anti N+1): trae Room + User(host) con JOIN.
            rooms = (
                Room.query.options(joinedload(Room.host))
                .filter_by(active=True)
                .all()
            )
            rooms_dict = [_room_to_dict(room) for room in rooms]
            return jsonify({'source': 'db', 'optimized': True, 'rooms': rooms_dict}), 200

        # Versión INEFICIENTE (N+1): Room se consulta primero y luego, al acceder
        # `room.host.username`, SQLAlchemy hace una consulta extra por cada Room.
        rooms = Room.query.filter_by(active=True).all()
        rooms_dict = [_room_to_dict(room) for room in rooms]
        return jsonify({'source': 'db', 'optimized': False, 'rooms': rooms_dict}), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@rooms_bp.route('/rooms/<room_id>', methods=['GET'])
def get_room(room_id: str):
    key = _cache_key(room_id)

    # 1. Intentar leer desde Redis (Cache Hit)
    cached = redis_client.get(key)
    if cached is not None:
        try:
            print(f"--> [CACHE HIT] Datos devueltos desde Redis para sala: {room_id}")
            return jsonify({'source': 'cache', 'room': json.loads(cached)}), 200
        except Exception:
            pass  # Si la estructura JSON falla, cae a la DB

    # 2. Si no está en Redis (Cache Miss), consultar la Base de Datos
    print(f"--> [CACHE MISS] Consultando DB para sala: {room_id}")

    # Usamos eager loading aquí porque el endpoint retorna host.username siempre.
    room = Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
    if room is None:
        return jsonify({'error': 'Room not found'}), 404

    # 3. Guardar en Redis usando JSON y TTL (setex)
    room_dict = _room_to_dict(room)
    redis_client.setex(key, CACHE_TTL, json.dumps(room_dict))

    return jsonify({'source': 'db', 'room': room_dict}), 200


@rooms_bp.route('/rooms/<room_id>/process-audio', methods=['POST'])
@jwt_user_required()
def process_audio(room_id: str):
    # Justificación de eager loading vs lazy (en este endpoint):
    # Aquí no iteramos por muchos objetos ni necesitamos relaciones adicionales.
    # La relación `host` no se usa directamente en la lógica, por eso no se hace eager.
    # En general:
    # - Si una relación se usa siempre al responder (como `Room.host.username` en GET /rooms/<id>),
    #   conviene eager loading.
    # - Relaciones grandes y opcionales (ej. messages/participants si existieran) podrían
    #   quedarse en lazy loading porque no siempre se necesitan.

    # Ejecuta la tarea en segundo plano
    task = process_audio_session.delay(str(room_id))
    return (
        jsonify({
            'message': 'Audio processing started',
            'task_id': task.id,
        }),
        202,
    )


@rooms_bp.route('/rooms/<room_id>', methods=['PUT'])
@jwt_user_required()
def put_room(room_id: str):

    payload = request.get_json(silent=True) or {}

    room = Room.query.filter_by(id=room_id).first()
    if not room:
        return jsonify({'error': 'Room not found'}), 404

    # Actualización simple (ajusta según campos esperados por tu frontend)
    if 'name' in payload:
        room.name = payload['name']
    if 'active' in payload:
        room.active = bool(payload['active'])

    db.session.commit()

    # Invalidación de caché: eliminar la clave obsoleta de Redis
    redis_client.delete(_cache_key(room_id))
    print(f"--> [CACHE INVALIDATED] Clave eliminada de Redis tras actualización")

    room = Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
    return jsonify({'updated': True, 'room': _room_to_dict(room)}), 200


@rooms_bp.route('/rooms/<room_id>', methods=['DELETE'])
@jwt_user_required()
def delete_room(room_id: str):

    room = Room.query.filter_by(id=room_id).first()
    if not room:
        return jsonify({'error': 'Room not found'}), 404

    deleted_room = {
        'id': room.id,
        'name': room.name,
        'active': room.active,
        'host_id': room.host_id,
    }

    db.session.delete(room)
    db.session.commit()

    # Invalidación de caché: eliminar clave de Redis
    redis_client.delete(_cache_key(room_id))
    print(f"--> [CACHE INVALIDATED] Clave eliminada de Redis tras eliminación")

    return jsonify({'deleted': True, 'room': deleted_room}), 200

