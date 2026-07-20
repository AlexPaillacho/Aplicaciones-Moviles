# Backend Flask (speak_english)

Este backend expone APIs en Flask y utiliza:
- Redis para **cache-aside** (TTL) y caché corta del usuario autenticado.
- Celery + Redis como broker/backend para tareas async (ej. `process_audio_session`).
- PostgreSQL opcional via `DATABASE_URL` (por defecto usa SQLite local en dev).

## Requisitos
- Python
- Redis

## Configuración (variables de entorno)
Las variables se leen desde `.env` (si existe) y/o del entorno.

Ejemplo mínimo:
```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

DATABASE_URL=sqlite:///dev.db

JWT_SECRET_KEY=dev-secret-change-me
```

## Levantar Redis
En tu máquina:
```bash
redis-server
```

(En Windows puede requerir instalar Redis como servicio o ejecutarlo desde el binario de Redis.)

## Crear tablas (SQLAlchemy)
En desarrollo (SQLite o Postgres), crea las tablas una vez:
1) Crea un shell:
```bash
python -c "from app import create_app, db; app=create_app(); app.app_context().push(); from app.models import User, Room; db.create_all(); print('OK')"
```

## Correr Celery worker
```bash
cd backend && celery -A app.tasks worker --loglevel=info
```

## Correr Flask
```bash
cd backend && python -c "from app import create_app; app=create_app(); app.run(host='0.0.0.0', port=5000, debug=True)"
```

## Probar la API
Usa Postman con la colección incluida:
- `backend/postman_collection.json`

Notas para la demo:
- `GET /rooms/list?optimized=false` muestra el patrón N+1 (lazy loading de `Room.host`).
- `GET /rooms/list?optimized=true` usa `joinedload(Room.host)` y reduce consultas.
- `GET /rooms/<id>` muestra cache miss/hit con Redis.
- `PUT /rooms/<id>` invalida la clave correspondiente en Redis.
- `POST /rooms/<id>/process-audio` requiere JWT.

