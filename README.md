# Speak English

App móvil de práctica de inglés hablado. Flutter (frontend) + Flask (backend), con Redis para caché/broker y Celery para procesar el audio en segundo plano.

## Arquitectura

- **Frontend**: Flutter, en la raíz de este repo (`lib/`).
- **Backend**: Flask, en `backend/`. Expone la API REST, usa Redis (cache-aside + broker de Celery) y Celery para procesar el audio de forma asíncrona.

## Requisitos

- Flutter SDK (Dart `^3.12.2`) — `flutter doctor -v` sin hallazgos pendientes para la plataforma objetivo (Android emulador/dispositivo).
- Python 3 y Redis, para el backend.
- Un emulador Android o dispositivo físico conectado (el flujo de grabación de audio necesita micrófono real; en emuladores hay que habilitar el micrófono del host en la configuración del AVD).

## 1. Levantar el backend

```bash
cd backend
pip install -r requirements.txt
```

Configura las variables de entorno (crea `backend/.env` si no existe):

```bash
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

DATABASE_URL=sqlite:///dev.db

JWT_SECRET_KEY=dev-secret-key-please-change-me-in-production-32chars
```

> En producción usa siempre una `JWT_SECRET_KEY` segura definida por variable de entorno, nunca el valor de ejemplo de arriba.

Levanta Redis:

```bash
redis-server
```

Crea las tablas (una sola vez):

```bash
python -c "from app import create_app, db; app=create_app(); app.app_context().push(); from app.models import User, Room; db.create_all(); print('OK')"
```

Corre el worker de Celery (deja esta terminal abierta):

```bash
cd backend && celery -A app.tasks worker --loglevel=info
```

En otra terminal, corre Flask con `host='0.0.0.0'` para que el emulador Android pueda alcanzarlo:

```bash
cd backend && python -c "from app import create_app; app=create_app(); app.run(host='0.0.0.0', port=5000, debug=True)"
```

Más detalle de configuración del backend (Postman, notas de caché/N+1) en [`backend/README.md`](backend/README.md).

## 2. Levantar la app Flutter

```bash
flutter pub get
```

La URL base del backend se inyecta en tiempo de compilación con `--dart-define`. Con un emulador Android, `10.0.2.2` apunta al `localhost` de la máquina host (es el valor por defecto en `lib/core/constants.dart` si no se especifica):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

En un dispositivo físico en la misma red, usa la IP local de tu máquina en vez de `10.0.2.2`.

Al conectar el celular/emulador por primera vez, la app pedirá permiso de micrófono (`RECORD_AUDIO` en Android) para poder grabar la práctica.

## Flujo de pantallas

```
LoginScreen ──(¿no tienes cuenta?)──► RegisterScreen ──(registro OK)──► LoginScreen
     │
     │ login OK
     ▼
RoomsListScreen ──(tap en una sala)──► RoomDetailScreen ──(grabar/detener)──► envío de audio
     │                                       │                                     │
     └── crear sala (FAB) ──────────────────┘                    polling a /tasks/<id> hasta
                                                                   SUCCESS/FAILURE, resultado
                                                                   mostrado en la misma pantalla
```

- **LoginScreen** / **RegisterScreen**: autenticación contra `/auth/*`, token guardado con `flutter_secure_storage`.
- **RoomsListScreen**: lista las salas (`GET /rooms/list`), pull-to-refresh, botón `+` para crear una sala nueva.
- **RoomDetailScreen**: detalle de la sala, botón "Eliminar" visible solo para el host, botón de grabar/detener (`package:record`) que envía el audio y muestra el resultado del procesamiento.

## Endpoints consumidos

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| POST | `/auth/register` | No | Crear cuenta |
| POST | `/auth/login` | No | Login, retorna `access_token` |
| GET | `/auth/me` | JWT | Usuario actual (restaurar sesión) |
| GET | `/rooms/list?optimized=true\|false` | No | Listado de salas |
| GET | `/rooms/<id>` | No | Detalle de una sala |
| POST | `/rooms` | JWT | Crear sala |
| PUT | `/rooms/<id>` | JWT | Editar sala |
| DELETE | `/rooms/<id>` | JWT | Eliminar sala (solo el host) |
| POST | `/rooms/<id>/process-audio` | JWT | Sube el audio grabado (multipart, campo `audio`) y dispara la tarea Celery. Responde `202` con `task_id` |
| GET | `/tasks/<task_id>` | JWT | Estado de la tarea Celery (`PENDING`/`SUCCESS`/`FAILURE` + `result`) |

## Pruebas

```bash
flutter test
```

Incluye:
- `test/widget_test.dart`: `LoginScreen` renderiza los campos email/contraseña y el botón "Ingresar".
- `test/services/auth_service_test.dart` y `test/services/rooms_service_test.dart`: tests unitarios de los servicios contra un backend simulado (`package:http/testing.dart`), sin necesitar el backend real corriendo.

## Nota sobre los audios subidos

Los audios grabados durante las pruebas se guardan en `backend/instance/uploads/`. Esa carpeta **no se versiona** (está en `.gitignore`) porque son archivos de prueba, no parte del código fuente.
