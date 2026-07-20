import os

from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from dotenv import load_dotenv

# Instancias globales (patrón recomendado para extensiones Flask)
# Importar desde otros módulos como: from app import db, jwt

db = SQLAlchemy()
jwt = JWTManager()


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
    # Recomendación: en producción usar variable de entorno fuerte.
    app.config['JWT_SECRET_KEY'] = os.getenv(
        'JWT_SECRET_KEY',
        'dev-secret-key-please-change-me-in-production-32chars-1234567890-abcdef',
    )

    # Inicializar extensiones
    db.init_app(app)
    jwt.init_app(app)

    # Import late-import para evitar ciclos de import
    from app.rooms import rooms_bp
    from app.auth.routes import auth_bp

    # Asegurar que los modelos se registren con SQLAlchemy antes de crear tablas
    # (especialmente útil en SQLite de desarrollo)
    from app import models  # noqa: F401

    app.register_blueprint(rooms_bp)
    app.register_blueprint(auth_bp)

    return app

