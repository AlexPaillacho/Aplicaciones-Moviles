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

JWT_SECRET_KEY=dev-secret-key-please-change-me-in-production-32chars

# Nota: en producción usa SIEMPRE una clave segura y definida por variable de entorno (nunca el valor por defecto).

# Taller Semana 13 (Bloque 8): en APP_ENV=prod, JWT_SECRET_KEY es
# obligatoria — la app no arranca sin ella (no acepta el valor de
# ejemplo de arriba). En dev (valor por defecto) sí se acepta, para no
# forzar un .env solo para levantar el proyecto localmente.
APP_ENV=dev

# Taller Semana 13: TTL del access token y del refresh token.
# Baja JWT_ACCESS_TOKEN_EXPIRES_MINUTES a 1 o 2 para forzar la renovación en el video.
JWT_ACCESS_TOKEN_EXPIRES_MINUTES=15
JWT_REFRESH_TOKEN_EXPIRES_DAYS=30
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

## Documentación de la API (Swagger/OpenAPI)
Fase 2 (Plan de fases pendientes): la especificación vive en `backend/openapi.yaml` (12 endpoints: 4 de auth + 8 de rooms/audio).

Con el backend corriendo, abre:
```
http://127.0.0.1:5000/apidocs
```
Sirve el spec crudo en `http://127.0.0.1:5000/static/openapi.yaml` (útil para importarlo en Postman/Insomnia como alternativa a `postman_collection.json`).

## Probar la API
Usa Postman con la colección incluida:
- `backend/postman_collection.json`

Notas para la demo:
- `GET /rooms/list?optimized=false` muestra el patrón N+1 (lazy loading de `Room.host`).
- `GET /rooms/list?optimized=true` usa `joinedload(Room.host)` y reduce consultas.
- `GET /rooms/list?page=2&per_page=5` (Fase 1): pagina el listado; la respuesta incluye `page`, `per_page`, `total`, `total_pages`.
- `GET /rooms/<id>` muestra cache miss/hit con Redis.
- `PUT /rooms/<id>` invalida la clave correspondiente en Redis.
- `POST /rooms/<id>/process-audio` requiere JWT.

### Ubicación aproximada (Taller Semana 14, Fase 4)
La app móvil puede enviar la ubicación **aproximada** del usuario (ya redondeada a ~1 km en el cliente) para una futura ordenación de salas por cercanía. Es **opcional**: si falta o es inválida se ignora y todo funciona igual que antes.
- `GET /rooms/list?optimized=true&lat=40.42&lng=-3.70` → la respuesta incluye `user_location` (`{"latitude": .., "longitude": ..}` o `null`).
- `POST /rooms` con `{"name": "...", "latitude": 40.42, "longitude": -3.7}` (JWT) → la respuesta incluye `user_location`.
- Al recibirla, el backend imprime en consola una línea `--> [LOCATION] ...` (útil para la demo junto con la respuesta en Postman).
- Por ahora **no se guarda** en la BD ni se ordena con ella: las salas todavía no tienen columnas de coordenadas (no hay cambios de esquema en esta fase).
- Validación aislada en `app/geo.py`. Pruebas: `cd backend && python -m unittest discover -s tests -v`.

