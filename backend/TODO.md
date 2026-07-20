# TODO - Backend Flask (speak_english)

- [x] Implementar `backend/app/__init__.py` con `create_app()` (Flask, Flask-SQLAlchemy, JWT, registro de blueprints rooms/auth)
- [x] Crear `backend/app/models.py` (User, Room con FK host->User y relación `Room.host`)
- [x] Crear `backend/app/auth/__init__.py` y `backend/app/auth/routes.py` (register/login + protección JWT + caché corta en Redis)
- [x] Modificar `backend/app/rooms/routes.py`:
  - [x] Reemplazar `_IN_MEMORY_DB` por SQLAlchemy real (Room)
  - [x] Implementar `GET /rooms/list` con parámetro `optimized=true/false` y demo N+1 con/ sin `joinedload(Room.host)`
  - [x] Proteger `POST /rooms/<id>/process-audio` con JWT
  - [x] Ajustar comentarios: por qué eager loading para host aquí y qué relaciones podrían quedarse lazy
  - [x] Mantener cache-aside Redis (TTL 300s) + invalidación en PUT/DELETE
- [x] Actualizar `backend/requirements.txt` (Flask-JWT-Extended + python-dotenv)
- [x] Generar `backend/postman_collection.json` con ejemplos de requests (register/login/rooms list cache hit/miss/invalidación/process-audio)
- [x] Crear `backend/README.md` con instrucciones de Redis, Celery worker y Flask + variables de entorno
- [ ] Ejecutar comandos de verificación (pip install, iniciar Redis, correr worker y Flask)

