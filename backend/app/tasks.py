import os
import time

from celery import Celery


celery_app = Celery(
    __name__,
    broker='redis://localhost:6379/0',
    backend='redis://localhost:6379/0',
)

# Configuración mínima explícita (opcional)
celery_app.conf.update(
    task_serializer='json',
    result_serializer='json',
    accept_content=['json'],
    timezone='UTC',
)

# En Windows el pool por defecto (prefork) NO funciona con Celery 4+/5:
# cada tarea termina en FAILURE con "ValueError: not enough values to
# unpack (expected 3, got 0)". Eso hacía que la app mostrara "El
# procesamiento del audio falló" aunque el audio sí se guardaba. El pool
# `solo` ejecuta las tareas en el mismo proceso y funciona en Windows.
if os.name == 'nt':
    os.environ.setdefault('FORKED_BY_MULTIPROCESSING', '1')
    celery_app.conf.worker_pool = 'solo'


@celery_app.task(name='tasks.process_audio_session')
def process_audio_session(room_id: str):
    """Simula un procesamiento pesado de audio para una sala."""
    time.sleep(5)
    return {
        'room_id': room_id,
        'status': 'processed',
        'detail': 'Audio session processed asynchronously',
    }

