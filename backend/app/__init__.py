import logging
import os
import secrets
from datetime import timedelta

from flask import Flask, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from flask_swagger_ui import get_swaggerui_blueprint
from dotenv import load_dotenv

# Instancias globales (patrón recomendado para extensiones Flask)
# Importar desde otros módulos como: from app import db, jwt

db = SQLAlchemy()
jwt = JWTManager()

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWAGGER_URL = '/apidocs'
OPENAPI_URL = '/static/openapi.yaml'


logger = logging.getLogger(__name__)


def _load_jwt_secret_key() -> str:
    """Resuelve `JWT_SECRET_KEY` desde el entorno (o `backend/.env`).

    - Producción (`APP_ENV=prod`): es obligatoria; si falta, la app no
      arranca en vez de firmar tokens con una clave improvisada.
    - Desarrollo: si no está definida se genera una clave aleatoria para
      este proceso (nunca hay una clave escrita en el código). Los tokens
      dejan de valer al reiniciar el servidor; para conservar la sesión
      entre reinicios define `JWT_SECRET_KEY` en `backend/.env`.
    """
    configured = os.getenv('JWT_SECRET_KEY')
    if configured:
        return configured

    if os.getenv('APP_ENV', 'dev') == 'prod':
        raise RuntimeError(
            'Falta JWT_SECRET_KEY en el entorno para el build de producción '
            '(APP_ENV=prod).'
        )

    logger.warning(
        'JWT_SECRET_KEY no está definida: se usa una clave temporal que se '
        'pierde al reiniciar el servidor. Defínela en backend/.env.'
    )
    return secrets.token_urlsafe(48)


def _load_database_url() -> str:
    """Resuelve DATABASE_URL o usa SQLite para desarrollo local."""
    # DATABASE_URL es configurable para pasar a Postgres en un entorno real.
    return os.getenv('DATABASE_URL', 'sqlite:///dev.db')


def _ensure_schema_upgrades(app: Flask) -> None:
    """Agrega columnas nuevas a tablas que ya existen en `dev.db`.

    `db.create_all()` solo crea tablas faltantes, no agrega columnas. Para
    que quien ya tiene una base de datos no tenga que borrarla ni correr
    una migración a mano, al arrancar se agrega (si falta)
    `audio_submissions.duration_seconds`. Si la tabla aún no existe no
    hace nada: `create_all()` la creará ya con la columna.
    """
    from sqlalchemy import inspect, text

    try:
        with app.app_context():
            inspector = inspect(db.engine)
            if 'audio_submissions' not in inspector.get_table_names():
                return
            columns = [c['name'] for c in inspector.get_columns('audio_submissions')]
            if 'duration_seconds' in columns:
                return
            with db.engine.begin() as conn:
                conn.execute(text(
                    'ALTER TABLE audio_submissions ADD COLUMN duration_seconds INTEGER'
                ))
            logger.info("Columna 'duration_seconds' agregada a audio_submissions")
    except Exception:  # noqa: BLE001 - no debe impedir que arranque el servidor
        logger.warning('No se pudo actualizar el esquema', exc_info=True)


def create_app() -> Flask:
    """Crea y configura la aplicación Flask.

    - Configura SQLAlchemy (SQLite local o DATABASE_URL)
    - Registra blueprints (rooms y auth)
    - Inicializa JWT
    """
    # Carga variables desde .env si existe (para desarrollo local)
    load_dotenv()
    logging.basicConfig(
        level=os.getenv('LOG_LEVEL', 'INFO'),
        format='%(levelname)s %(name)s: %(message)s',
    )

    app = Flask(__name__)

    # Configuración base
    app.config['SQLALCHEMY_DATABASE_URI'] = _load_database_url()
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Clave secreta para firmar JWT
    # Bloque 8: en producción (APP_ENV=prod) es obligatoria por variable
    # de entorno — ver `_load_jwt_secret_key()`.
    app.config['JWT_SECRET_KEY'] = _load_jwt_secret_key()

    # Taller Semana 13: TTL corto configurable por entorno para poder
    # forzar la renovación del token en el video (bajarlo a 1-2 min).
    # Por defecto 15 min en access token y 30 días en refresh token.
    app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(
        minutes=int(os.getenv('JWT_ACCESS_TOKEN_EXPIRES_MINUTES', '15'))
    )
    app.config['JWT_REFRESH_TOKEN_EXPIRES'] = timedelta(
        days=int(os.getenv('JWT_REFRESH_TOKEN_EXPIRES_DAYS', '30'))
    )

    # Inicializar extensiones
    db.init_app(app)
    jwt.init_app(app)

    # Autorizar peticiones desde el frontend Flutter en desarrollo local
    # (el navegador considera cada puerto un origen distinto). Acotado a
    # localhost/127.0.0.1 en cualquier puerto; quitar o restringir antes
    # de distribuir la app.
    CORS(
        app,
        resources={r"/*": {"origins": [
            r"http://localhost:*",
            r"http://127.0.0.1:*",
        ]}},
        supports_credentials=True,
    )

    # Import late-import para evitar ciclos de import
    from app.rooms import rooms_bp
    from app.auth.routes import auth_bp

    # Asegurar que los modelos se registren con SQLAlchemy antes de crear tablas
    # (especialmente útil en SQLite de desarrollo)
    from app import models  # noqa: F401

    app.register_blueprint(rooms_bp)
    app.register_blueprint(auth_bp)

    _ensure_schema_upgrades(app)

    # Fase 2 (Plan de fases pendientes): documentación de APIs con
    # Swagger/OpenAPI. `openapi.yaml` vive en la raíz de `backend/` (junto
    # a `run.py`, no dentro de `app/static/`) para que sea fácil de
    # encontrar y editar; esta ruta lo sirve puntualmente en
    # `/static/openapi.yaml` (SIN exponer el resto de `backend/` como
    # estático, que tendría `.env`/`instance/` con la DB). La UI de
    # Swagger queda montada en `/apidocs`.
    @app.route(OPENAPI_URL)
    def openapi_spec():
        return send_from_directory(
            BACKEND_ROOT, 'openapi.yaml', mimetype='application/yaml'
        )

    swagger_bp = get_swaggerui_blueprint(
        SWAGGER_URL, OPENAPI_URL, config={'app_name': 'Speak English API'}
    )
    app.register_blueprint(swagger_bp, url_prefix=SWAGGER_URL)

    return app

