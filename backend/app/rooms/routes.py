import json
import os
import time
from datetime import datetime, timezone

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from sqlalchemy.orm import joinedload
from werkzeug.utils import secure_filename

from app import db
from app.cache import redis_client
from app.models import AudioSubmission, Room
from app.tasks import celery_app, process_audio_session

from app.auth.routes import jwt_user_required

# Endpoint POST /rooms/<room_id>/process-audio:
# Ejecuta la tarea pesada en segundo plano (Celery) y retorna 202 con el task_id.

rooms_bp = Blueprint('rooms', __name__)

CACHE_TTL = 300  # Tiempo de vida de la caché: 5 minutos (300 segundos)

UPLOAD_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    'instance', 'uploads',
)
os.makedirs(UPLOAD_DIR, exist_ok=True)


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
        # ISO 8601 en UTC. IMPORTANTE: se agrega el sufijo 'Z' a mano
        # porque `datetime.utcnow()` guarda un datetime "naive" (sin
        # tzinfo); sin el 'Z', `DateTime.parse` en Dart lo interpretaría
        # como hora LOCAL del dispositivo en vez de UTC, y la comparación
        # de conflictos (`expected_updated_at` en `put_room`) quedaría
        # desfasada por el huso horario del cliente.
        'updated_at': room.updated_at.isoformat() + 'Z',
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


@rooms_bp.route('/rooms', methods=['POST'])
@jwt_user_required()
def create_room():
    payload = request.get_json(silent=True) or {}
    name = payload.get('name')

    if not name:
        return jsonify({'error': 'name es requerido'}), 400

    host_id = int(get_jwt_identity())

    room = Room(name=name, active=True, host_id=host_id)
    db.session.add(room)
    db.session.commit()

    room = Room.query.options(joinedload(Room.host)).filter_by(id=room.id).first()
    return jsonify({'created': True, 'room': _room_to_dict(room)}), 201


@rooms_bp.route('/rooms/<room_id>/process-audio', methods=['POST'])
@jwt_user_required()
def process_audio(room_id: str):
    audio_file = request.files.get('audio')
    saved_filename = None

    if audio_file:
        original_name = secure_filename(audio_file.filename or 'audio.m4a')
        saved_filename = f"room_{room_id}_{int(time.time())}_{original_name}"
        audio_file.save(os.path.join(UPLOAD_DIR, saved_filename))

    task = process_audio_session.delay(str(room_id))

    # Persistimos el envío en la DB (antes esto solo vivía en Celery/Redis,
    # que es efímero). user_id sale del JWT: quien envía el audio, no
    # necesariamente el host de la sala.
    submission = AudioSubmission(
        room_id=int(room_id),
        user_id=int(get_jwt_identity()),
        task_id=task.id,
        saved_filename=saved_filename,
        status='PENDING',
    )
    db.session.add(submission)
    db.session.commit()

    return (
        jsonify({
            'message': 'Audio processing started',
            'task_id': task.id,
            'saved_file': saved_filename,
            'submission_id': submission.id,
        }),
        202,
    )


def _sync_submission_from_celery(task_id: str, celery_result) -> None:
    """Sincroniza el estado/resultado de Celery hacia la fila persistida en
    AudioSubmission. Se llama de forma "perezosa" cuando se consulta
    GET /tasks/<id> (que la app ya pollea), evitando que el worker de
    Celery necesite contexto de Flask/DB para escribir directamente."""
    submission = AudioSubmission.query.filter_by(task_id=task_id).first()
    if submission is None:
        return

    if submission.status == celery_result.state:
        return  # nada que actualizar

    submission.status = celery_result.state
    if celery_result.state == 'SUCCESS':
        submission.result_json = json.dumps(celery_result.result)
    elif celery_result.state == 'FAILURE':
        submission.result_json = json.dumps({'error': str(celery_result.info)})

    db.session.commit()


@rooms_bp.route('/tasks/<task_id>', methods=['GET'])
@jwt_user_required()
def task_status(task_id: str):
    result = celery_app.AsyncResult(task_id)

    _sync_submission_from_celery(task_id, result)

    response = {'task_id': task_id, 'state': result.state}

    if result.state == 'SUCCESS':
        response['result'] = result.result
    elif result.state == 'FAILURE':
        response['error'] = str(result.info)

    return jsonify(response), 200


def _submission_to_dict(submission: AudioSubmission) -> dict:
    return {
        'id': submission.id,
        'room_id': submission.room_id,
        'user_id': submission.user_id,
        'task_id': submission.task_id,
        'status': submission.status,
        'result': json.loads(submission.result_json) if submission.result_json else None,
        'created_at': submission.created_at.isoformat(),
    }


@rooms_bp.route('/rooms/<room_id>/submissions', methods=['GET'])
@jwt_user_required()
def list_submissions(room_id: str):
    """Historial real (persistido en DB) de envíos de audio de una sala,
    a diferencia de GET /tasks/<id> que solo consulta un envío puntual
    contra Celery/Redis (efímero)."""
    submissions = (
        AudioSubmission.query.filter_by(room_id=room_id)
        .order_by(AudioSubmission.created_at.desc())
        .all()
    )
    return jsonify({
        'room_id': int(room_id),
        'submissions': [_submission_to_dict(s) for s in submissions],
    }), 200


def _parse_iso(value):
    """Parsea un timestamp ISO 8601 a un datetime NAIVE en UTC (sin
    tzinfo), para que se pueda comparar directamente con `Room.updated_at`
    (que SQLAlchemy/SQLite guardan naive). Devuelve None si viene vacío o
    malformado (se trata como 'sin base de comparación', no como error).
    """
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace('Z', '+00:00'))
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


@rooms_bp.route('/rooms/<room_id>', methods=['PUT'])
@jwt_user_required()
def put_room(room_id: str):

    payload = request.get_json(silent=True) or {}

    room = Room.query.filter_by(id=room_id).first()
    if not room:
        return jsonify({'error': 'Room not found'}), 404

    # ===== Resolución de conflictos (taller Semana 12) =====
    # El cliente manda `expected_updated_at`: el `updated_at` que tenía la
    # sala en su caché local al momento en que el usuario encoló esta
    # edición (offline). Si el servidor tiene un `updated_at` MÁS NUEVO que
    # ese valor, significa que la sala cambió mientras el cliente estaba
    # desconectado -> hay conflicto real, y gana el servidor: se rechaza la
    # escritura local con 409 y se devuelve el estado actual para que el
    # cliente descarte su edición y se realinee.
    expected_updated_at = _parse_iso(payload.get('expected_updated_at'))
    # Comparamos truncado a microsegundos ausentes de milisegundos de red
    # (SQLite guarda microsegundos; alcanza con comparar directamente).
    if expected_updated_at is not None and room.updated_at > expected_updated_at:
        return jsonify({
            'error': 'conflict',
            'message': 'La sala fue modificada en el servidor mientras estabas sin conexión.',
            'room': _room_to_dict(
                Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
            ),
        }), 409

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