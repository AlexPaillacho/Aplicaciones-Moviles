import os
from datetime import timedelta

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from dotenv import load_dotenv

# Instancias globales (patrón recomendado para extensiones Flask)
# Importar desde otros módulos como: from app import db, jwt

db = SQLAlchemy()
jwt = JWTManager()


_DEV_JWT_SECRET_KEY = 'dev-secret-key-please-change-me-in-production-32chars-1234567890-abcdef'


def _load_jwt_secret_key() -> str:
    """Resuelve `JWT_SECRET_KEY`.

    Taller Semana 13 (Bloque 8, verificación de seguridad): en
    desarrollo (`APP_ENV` distinto de `prod`) se acepta el valor de
    ejemplo de abajo para no obligar a nadie a configurar un `.env` solo
    para levantar el proyecto localmente. En producción (`APP_ENV=prod`)
    ese valor de ejemplo ya no se acepta — si no se definió
    `JWT_SECRET_KEY` por variable de entorno, la app falla al arrancar
    en vez de firmar tokens con una clave que cualquiera puede leer en
    este mismo archivo (mismo criterio que `ApiClient.resolveBaseUrl()`
    en el cliente Flutter, que tampoco arranca en producción sin
    `API_BASE_URL` explícito).
    """
    configured = os.getenv('JWT_SECRET_KEY')
    app_env = os.getenv('APP_ENV', 'dev')

    if app_env == 'prod':
        if not configured:
            raise RuntimeError(
                'Falta JWT_SECRET_KEY en el entorno para el build de producción '
                '(APP_ENV=prod). No se usa la clave de ejemplo de desarrollo.'
            )
        return configured

    return configured or _DEV_JWT_SECRET_KEY


def _load_database_url() -> str:
    """Resuelve DATABASE_URL o usa SQLite para desarrollo local."""
    # DATABASE_URL es configurable para pasar a Postgres en un entorno real.
    return os.getenv('DATABASE_URL', 'sqlite:///dev.db')


def create_app() -> Flask:
    """Crea y configura la aplicación Flask.

    - Configura SQLAlchemy (SQLite local o DATABASE_URL)
    - Registra blueprints (rooms y auth)
    - Inicializa JWT
    """
    # Carga variables desde .env si existe (para desarrollo local)
    load_dotenv()

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

    return app

