"""Lógica de apoyo de las rutas de salas.

Las rutas (`routes.py`) solo reciben la petición y arman la respuesta;
aquí viven la serialización de modelos, el guardado de audios y la
sincronización con Celery.
"""
import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Optional

from werkzeug.datastructures import FileStorage
from werkzeug.utils import secure_filename

from app import db
from app.models import AudioSubmission, Room
from app.tasks import celery_app

logger = logging.getLogger(__name__)

# Un .m4a con contenido real pesa bastante más que esto; por debajo se
# trata como grabación vacía y se rechaza en vez de guardarla.
MIN_AUDIO_BYTES = 1024

DEFAULT_AUDIO_NAME = 'audio.m4a'

# backend/instance/uploads (esta carpeta no se versiona).
UPLOAD_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    'instance',
    'uploads',
)

_FINAL_STATES = ('SUCCESS', 'FAILURE')


def room_to_dict(room: Room) -> dict:
    """Convierte una sala a un dict JSON-friendly.

    Nota: para demostrar N+1, `room.host` se accede aquí; con
    `joinedload(Room.host)` en la consulta no genera consultas extra.
    """
    host = room.host
    return {
        'id': room.id,
        'name': room.name,
        'active': room.active,
        # ISO 8601 en UTC. El sufijo 'Z' se agrega a mano porque la fecha
        # se guarda "naive" (sin tzinfo); sin él, `DateTime.parse` en Dart
        # la interpretaría como hora LOCAL del dispositivo y la
        # comparación de conflictos (`expected_updated_at` en `put_room`)
        # quedaría desfasada por el huso horario del cliente.
        'updated_at': room.updated_at.isoformat() + 'Z',
        'host': {
            'id': host.id if host else None,
            'username': host.username if host else None,
        },
    }


def submission_to_dict(submission: AudioSubmission) -> dict:
    """Convierte un envío de audio a un dict JSON-friendly."""
    return {
        'id': submission.id,
        'room_id': submission.room_id,
        'user_id': submission.user_id,
        'task_id': submission.task_id,
        'saved_filename': submission.saved_filename,
        'duration_seconds': submission.duration_seconds,
        'status': submission.status,
        'result': (
            json.loads(submission.result_json)
            if submission.result_json
            else None
        ),
        # UTC explícito (sufijo 'Z'): sin él, Dart interpretaría la fecha
        # como hora local del dispositivo.
        'created_at': submission.created_at.isoformat() + 'Z',
    }


def parse_iso(value: Optional[str]) -> Optional[datetime]:
    """Parsea un timestamp ISO 8601 a un datetime NAIVE en UTC.

    Así se puede comparar directamente con `Room.updated_at` (que
    SQLAlchemy/SQLite guardan naive). Devuelve `None` si viene vacío o
    malformado: se trata como "sin base de comparación", no como error.
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


def parse_duration_seconds(value) -> Optional[int]:
    """Duración en segundos enviada por la app (campo de formulario).

    Devuelve `None` si falta o no es un número razonable (0 a 24 h): es un
    dato informativo para el historial, nunca debe rechazar el audio.
    """
    try:
        seconds = int(round(float(value)))
    except (TypeError, ValueError):
        return None
    return seconds if 0 <= seconds <= 86400 else None


def uploaded_size(audio_file: FileStorage) -> int:
    """Tamaño real en bytes del archivo recibido.

    Una grabación fallida en el cliente llega como un archivo de 0 bytes
    o con solo la cabecera del contenedor.
    """
    audio_file.stream.seek(0, os.SEEK_END)
    size_bytes = audio_file.stream.tell()
    audio_file.stream.seek(0)
    return size_bytes


def save_audio(audio_file: FileStorage, room_id: int) -> str:
    """Guarda el audio en `UPLOAD_DIR` y devuelve el nombre del archivo."""
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    original_name = secure_filename(audio_file.filename or DEFAULT_AUDIO_NAME)
    saved_filename = f'room_{room_id}_{int(time.time())}_{original_name}'
    audio_file.save(os.path.join(UPLOAD_DIR, saved_filename))
    return saved_filename


def sync_submission_from_celery(task_id: str, celery_result) -> None:
    """Sincroniza el estado/resultado de Celery hacia `AudioSubmission`.

    Se llama de forma "perezosa" cuando se consulta `GET /tasks/<id>`
    (que la app ya consulta), evitando que el worker de Celery necesite
    contexto de Flask/DB para escribir directamente.
    """
    submission = AudioSubmission.query.filter_by(task_id=task_id).first()
    if submission is None:
        return

    # Un estado final ya guardado no se pisa (ej. un envío cuya cola no
    # estaba disponible: Celery no lo conoce y respondería PENDING).
    if submission.status in _FINAL_STATES:
        return

    if submission.status == celery_result.state:
        return  # nada que actualizar

    submission.status = celery_result.state
    if celery_result.state == 'SUCCESS':
        submission.result_json = json.dumps(celery_result.result)
    elif celery_result.state == 'FAILURE':
        submission.result_json = json.dumps({'error': str(celery_result.info)[:500]})

    db.session.commit()


def refresh_pending_submissions(submissions: list) -> None:
    """Actualiza desde Celery los envíos que aún no terminaron.

    Así el historial refleja el estado real aunque la app no haya llegado
    a consultar `GET /tasks/<id>`. Si Redis/Celery no responde, el listado
    sigue funcionando con el último estado guardado.
    """
    for submission in submissions:
        if submission.status in _FINAL_STATES:
            continue
        try:
            sync_submission_from_celery(
                submission.task_id, celery_app.AsyncResult(submission.task_id)
            )
        except Exception:  # noqa: BLE001 - el historial no debe caer por esto
            logger.warning(
                'No se pudo sincronizar el envío %s con Celery',
                submission.id,
                exc_info=True,
            )
            db.session.rollback()
