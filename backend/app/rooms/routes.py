import json
import logging
import uuid

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from sqlalchemy.orm import joinedload

from app import db
from app.auth.routes import jwt_user_required
from app.cache import redis_client
from app.geo import parse_coordinates
from app.models import AudioSubmission, Room
from app.rooms.services import (
    MIN_AUDIO_BYTES,
    parse_duration_seconds,
    parse_iso,
    refresh_pending_submissions,
    room_to_dict,
    save_audio,
    submission_to_dict,
    sync_submission_from_celery,
    uploaded_size,
)
from app.tasks import celery_app, process_audio_session

logger = logging.getLogger(__name__)

rooms_bp = Blueprint('rooms', __name__)

CACHE_TTL = 300  # Tiempo de vida de la caché: 5 minutos (300 segundos)

DEFAULT_PAGE = 1
DEFAULT_PER_PAGE = 10
MAX_PER_PAGE = 50  # tope para que un cliente no pida el listado completo


def _cache_key(room_id: str) -> str:
    return f'rooms:{room_id}'


def _int_arg(name: str, default: int) -> int:
    """Lee un parámetro entero de la query string; si falta o es inválido
    devuelve `default`."""
    try:
        return int(request.args.get(name, default))
    except (TypeError, ValueError):
        return default


def _pagination() -> tuple[int, int]:
    """Devuelve `(page, per_page)` ya acotados a valores válidos."""
    page = max(_int_arg('page', DEFAULT_PAGE), 1)
    per_page = min(max(_int_arg('per_page', DEFAULT_PER_PAGE), 1), MAX_PER_PAGE)
    return page, per_page


def _total_pages(total: int, per_page: int) -> int:
    return (total + per_page - 1) // per_page if total else 0


def _find_room(room_id: str):
    """Busca una sala por id (texto de la URL); `None` si no existe."""
    return db.session.get(Room, int(room_id)) if room_id.isdigit() else None


# ===== Estrategia Cache-Aside e invalidación =====

# GET lista de salas.
# `GET /rooms/list` es público (sin JWT): para la demo se compara N+1
# (lazy loading) contra eager loading (`joinedload(Room.host)`) sin que la
# autenticación afecte el número de consultas.
#
# Parámetros opcionales: `optimized`, `page`/`per_page` (por defecto 1 y
# 10, tope 50) y `lat`/`lng` (ubicación aproximada del usuario: se valida,
# se registra y se devuelve en `user_location`, pero todavía no ordena ni
# se persiste). Se ordena por `id` para que la paginación sea estable.
@rooms_bp.route('/rooms/list', methods=['GET'])
def list_rooms():
    try:
        optimized = request.args.get('optimized', 'false').lower() == 'true'
        page, per_page = _pagination()

        user_location = parse_coordinates(
            request.args.get('lat'), request.args.get('lng')
        )
        if user_location:
            logger.info(
                '--> [LOCATION] GET /rooms/list con ubicación aproximada: '
                'lat=%s lng=%s',
                user_location['latitude'],
                user_location['longitude'],
            )

        query = Room.query.filter_by(active=True)
        if optimized:
            # Versión CORREGIDA (anti N+1): trae Room + User(host) con JOIN.
            query = query.options(joinedload(Room.host))
        # Versión INEFICIENTE (N+1, optimized=False): al acceder luego a
        # `room.host.username` SQLAlchemy hace una consulta extra por sala.

        total = query.order_by(None).count()
        rooms = (
            query.order_by(Room.id.asc())
            .offset((page - 1) * per_page)
            .limit(per_page)
            .all()
        )

        return jsonify({
            'source': 'db',
            'optimized': optimized,
            'user_location': user_location,
            'page': page,
            'per_page': per_page,
            'total': total,
            'total_pages': _total_pages(total, per_page),
            'rooms': [room_to_dict(r) for r in rooms],
        }), 200

    except Exception:  # noqa: BLE001 - se registra y se responde 500
        logger.exception('Error al listar salas')
        return jsonify({'error': 'Error interno al listar las salas'}), 500


@rooms_bp.route('/rooms/<room_id>', methods=['GET'])
def get_room(room_id: str):
    key = _cache_key(room_id)

    # 1. Intentar leer desde Redis (Cache Hit)
    cached = redis_client.get(key)
    if cached is not None:
        try:
            room_dict = json.loads(cached)
        except ValueError:
            pass  # JSON corrupto: cae a la DB
        else:
            logger.info(
                '--> [CACHE HIT] Datos devueltos desde Redis para sala: %s',
                room_id,
            )
            return jsonify({'source': 'cache', 'room': room_dict}), 200

    # 2. Si no está en Redis (Cache Miss), consultar la Base de Datos
    logger.info('--> [CACHE MISS] Consultando DB para sala: %s', room_id)

    # Eager loading: el endpoint siempre devuelve host.username.
    room = Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
    if room is None:
        return jsonify({'error': 'Room not found'}), 404

    # 3. Guardar en Redis usando JSON y TTL (setex)
    room_dict = room_to_dict(room)
    redis_client.setex(key, CACHE_TTL, json.dumps(room_dict))

    return jsonify({'source': 'db', 'room': room_dict}), 200


@rooms_bp.route('/rooms', methods=['POST'])
@jwt_user_required()
def create_room():
    payload = request.get_json(silent=True) or {}
    name = payload.get('name')

    if not name:
        # 422 (validación), no 400: la petición está bien formada, lo que
        # falla es el dato.
        return jsonify({'error': 'name es requerido'}), 422

    host_id = int(get_jwt_identity())

    # Ubicación aproximada opcional del usuario (`latitude`/`longitude`):
    # se valida, se registra y se devuelve en `user_location`; todavía NO
    # se guarda en la sala.
    user_location = parse_coordinates(
        payload.get('latitude'), payload.get('longitude')
    )
    if user_location:
        logger.info(
            '--> [LOCATION] POST /rooms con ubicación aproximada: '
            'lat=%s lng=%s',
            user_location['latitude'],
            user_location['longitude'],
        )

    room = Room(name=name, active=True, host_id=host_id)
    db.session.add(room)
    db.session.commit()

    room = Room.query.options(joinedload(Room.host)).filter_by(id=room.id).first()
    return jsonify({
        'created': True,
        'room': room_to_dict(room),
        'user_location': user_location,
    }), 201


# POST /rooms/<room_id>/process-audio: guarda el audio y ejecuta la tarea
# pesada en segundo plano (Celery); responde 202 con el task_id.
@rooms_bp.route('/rooms/<room_id>/process-audio', methods=['POST'])
@jwt_user_required()
def process_audio(room_id: str):
    room = _find_room(room_id)
    if room is None:
        return jsonify({'error': 'Room not found'}), 404

    audio_file = request.files.get('audio')
    if audio_file is None:
        return jsonify({'error': 'audio es requerido'}), 422

    size_bytes = uploaded_size(audio_file)
    if size_bytes < MIN_AUDIO_BYTES:
        return jsonify({
            'error': 'El audio está vacío o es demasiado corto',
        }), 422

    saved_filename = save_audio(audio_file, room.id)

    # El audio ya está guardado: encolar el procesamiento es un paso
    # aparte. Si Redis/Celery no responde, el envío se registra igual
    # (queda como FAILURE de procesamiento) en vez de responder 500 y
    # hacer creer al usuario que el audio no se guardó.
    try:
        task_id = process_audio_session.delay(str(room.id)).id
        status = 'PENDING'
        result_json = None
    except Exception as exc:  # noqa: BLE001
        logger.exception('No se pudo encolar el procesamiento del audio')
        task_id = f'local-{uuid.uuid4().hex}'
        status = 'FAILURE'
        result_json = json.dumps({'error': f'Cola no disponible: {exc}'[:500]})

    # Persistimos el envío en la DB (Celery/Redis es efímero). user_id sale
    # del JWT: quien envía el audio, no necesariamente el host de la sala.
    submission = AudioSubmission(
        room_id=room.id,
        user_id=int(get_jwt_identity()),
        task_id=task_id,
        saved_filename=saved_filename,
        duration_seconds=parse_duration_seconds(request.form.get('duration_seconds')),
        status=status,
        result_json=result_json,
    )
    db.session.add(submission)
    db.session.commit()

    return jsonify({
        'message': 'Audio guardado',
        'task_id': task_id,
        'saved_file': saved_filename,
        'size_bytes': size_bytes,
        'submission_id': submission.id,
        'processing_status': status,
    }), 202


@rooms_bp.route('/tasks/<task_id>', methods=['GET'])
@jwt_user_required()
def task_status(task_id: str):
    result = celery_app.AsyncResult(task_id)

    sync_submission_from_celery(task_id, result)

    response = {'task_id': task_id, 'state': result.state}

    if result.state == 'SUCCESS':
        response['result'] = result.result
    elif result.state == 'FAILURE':
        response['error'] = str(result.info)

    return jsonify(response), 200


@rooms_bp.route('/rooms/<room_id>/submissions', methods=['GET'])
@jwt_user_required()
def list_submissions(room_id: str):
    """Historial persistido (en DB) de los envíos de audio DEL USUARIO
    autenticado en una sala, del más reciente al más antiguo y paginado
    (`page`, `per_page`; por defecto 10, tope 50). A diferencia de
    `GET /tasks/<id>`, que consulta un envío puntual contra Celery/Redis
    (efímero), esto sale de la base de datos."""
    room = _find_room(room_id)
    if room is None:
        return jsonify({'error': 'Room not found'}), 404

    page, per_page = _pagination()

    query = AudioSubmission.query.filter_by(
        room_id=room.id, user_id=int(get_jwt_identity())
    )
    total = query.count()
    submissions = (
        query.order_by(AudioSubmission.created_at.desc(), AudioSubmission.id.desc())
        .offset((page - 1) * per_page)
        .limit(per_page)
        .all()
    )
    refresh_pending_submissions(submissions)

    return jsonify({
        'room_id': room.id,
        'page': page,
        'per_page': per_page,
        'total': total,
        'total_pages': _total_pages(total, per_page),
        'submissions': [submission_to_dict(s) for s in submissions],
    }), 200


@rooms_bp.route('/rooms/<room_id>', methods=['PUT'])
@jwt_user_required()
def put_room(room_id: str):
    payload = request.get_json(silent=True) or {}

    room = Room.query.filter_by(id=room_id).first()
    if not room:
        return jsonify({'error': 'Room not found'}), 404

    # ===== Resolución de conflictos (offline-first) =====
    # El cliente manda `expected_updated_at`: el `updated_at` que tenía la
    # sala en su caché local cuando el usuario encoló la edición offline.
    # Si el servidor tiene un `updated_at` MÁS NUEVO, la sala cambió
    # mientras el cliente estaba desconectado -> conflicto real, y gana el
    # servidor: se rechaza la escritura con 409 y se devuelve el estado
    # actual para que el cliente descarte su edición y se realinee.
    expected_updated_at = parse_iso(payload.get('expected_updated_at'))
    if expected_updated_at is not None and room.updated_at > expected_updated_at:
        current = Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
        return jsonify({
            'error': 'conflict',
            'message': 'La sala fue modificada en el servidor mientras estabas sin conexión.',
            'room': room_to_dict(current),
        }), 409

    if 'name' in payload:
        room.name = payload['name']
    if 'active' in payload:
        room.active = bool(payload['active'])

    db.session.commit()

    # Invalidación de caché: eliminar la clave obsoleta de Redis
    redis_client.delete(_cache_key(room_id))
    logger.info('--> [CACHE INVALIDATED] Clave eliminada de Redis tras actualización')

    room = Room.query.options(joinedload(Room.host)).filter_by(id=room_id).first()
    return jsonify({'updated': True, 'room': room_to_dict(room)}), 200


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
    logger.info('--> [CACHE INVALIDATED] Clave eliminada de Redis tras eliminación')

    return jsonify({'deleted': True, 'room': deleted_room}), 200
