import json
import os
from functools import wraps

from flask import Blueprint, g, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt_identity, jwt_required
from werkzeug.security import check_password_hash, generate_password_hash

from app.cache import redis_client
from app import db
from app.models import User



auth_bp = Blueprint('auth', __name__)


# TTL corto para reducir consultas redundantes en requests consecutivos
AUTH_USER_CACHE_TTL_SECONDS = int(os.getenv('AUTH_USER_CACHE_TTL_SECONDS', '30'))


def _auth_user_cache_key(user_id: int | str) -> str:
    return f'auth:user:{user_id}'


def _serialize_user_min(user: User) -> dict:
    return {
        'id': user.id,
        'username': user.username,
        'email': user.email,
    }


def _get_authenticated_user_one_query():
    """Obtiene el usuario autenticado.

    Estrategia:
    - Primero intenta Redis (cache hit)
    - Si hay miss, consulta una sola vez en DB por PK y cachea

    El decorador protege rutas y asegura que la validación del JWT no provoque
    múltiples consultas repetidas dentro de la misma request.
    """
    if getattr(g, 'current_user', None) is not None:
        return g.current_user

    jwt_user_id = get_jwt_identity()
    # identity se guarda como string, convertimos para query por PK

    cache_key = _auth_user_cache_key(jwt_user_id)

    cached = redis_client.get(cache_key)
    if cached:
        try:
            data = json.loads(cached)
            g.current_user = data
            return g.current_user
        except Exception:
            # Si el JSON guardado está corrupto, cae a DB
            pass

    user = User.query.get(int(jwt_user_id))  # UNA sola consulta por PK

    if not user:
        g.current_user = None
        return None

    data = _serialize_user_min(user)
    redis_client.setex(cache_key, AUTH_USER_CACHE_TTL_SECONDS, json.dumps(data))

    g.current_user = data
    return g.current_user


def jwt_user_required():
    """Decorador reutilizable para proteger rutas.

    - jwt_required() valida firma y expiración del JWT.
    - Luego obtiene el usuario autenticado con UNA consulta o desde Redis.
    """

    def decorator(fn):
        @wraps(fn)
        @jwt_required()
        def wrapper(*args, **kwargs):
            user = _get_authenticated_user_one_query()
            if not user:
                return jsonify({'error': 'Usuario no encontrado'}), 401
            # g.current_user ya está listo y cacheado en Redis
            return fn(*args, **kwargs)

        return wrapper

    return decorator


@auth_bp.route('/auth/register', methods=['POST'])
def register():
    payload = request.get_json(silent=True) or {}

    username = payload.get('username')
    email = payload.get('email')
    password = payload.get('password')

    if not username or not email or not password:
        return jsonify({'error': 'username, email y password son requeridos'}), 400

    # Evitar duplicados
    existing = User.query.filter_by(email=email).first()
    if existing:
        return jsonify({'error': 'Email ya registrado'}), 409

    user = User(
        username=username,
        email=email,
        password_hash=generate_password_hash(password),
    )

    db.session.add(user)
    db.session.commit()

    return jsonify({'registered': True, 'user': {'id': user.id, 'email': user.email}}), 201


@auth_bp.route('/auth/login', methods=['POST'])
def login():
    payload = request.get_json(silent=True) or {}

    email = payload.get('email')
    password = payload.get('password')

    if not email or not password:
        return jsonify({'error': 'email y password son requeridos'}), 400

    user = User.query.filter_by(email=email).first()
    if not user:
        return jsonify({'error': 'Credenciales inválidas'}), 401

    if not check_password_hash(user.password_hash, password):
        return jsonify({'error': 'Credenciales inválidas'}), 401

    # identity guardada como string (JWT en Flask-JWT-Extended suele serializar/validar como str)
    access_token = create_access_token(identity=str(user.id))


    return jsonify({'access_token': access_token}), 200


@auth_bp.route('/auth/me', methods=['GET'])
@jwt_user_required()
def me():
    # g.current_user puede venir de Redis o DB
    return jsonify({'user': g.current_user}), 200

