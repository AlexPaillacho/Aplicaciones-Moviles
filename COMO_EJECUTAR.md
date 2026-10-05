# Cómo ejecutar Speak English

Este ZIP contiene solo lo necesario para **correr** la app (backend + frontend Flutter para Android/Web). Se excluyeron a propósito: `__pycache__`, cachés de compilación (`.dart_tool`, `ephemeral`), y las carpetas de plataforma `ios/`, `macos/`, `windows/`, `linux/` (no necesarias para probar en Android/emulador o Web). Si necesitas correrlo en esas plataformas, vuelve a generar los archivos de plataforma con `flutter create .` dentro de esta carpeta.

## 1. Backend (Flask + Redis + Celery)

```bash
cd backend
python -m venv venv
source venv/bin/activate        # En Windows: venv\Scripts\activate
pip install -r requirements.txt

# Redis debe estar corriendo (localmente o vía Docker):
#   docker run -p 6379:6379 redis

python seed_db.py                # crea las tablas y siembra la base de datos de desarrollo
python run.py                    # levanta el servidor Flask en http://127.0.0.1:5000

# En otra terminal, el worker de Celery (necesario para procesar audio):
celery -A app.tasks worker --loglevel=info -P solo
```

Documentación interactiva de la API una vez levantado el backend:
`http://127.0.0.1:5000/apidocs`

## 2. App Flutter

```bash
flutter pub get
flutter run                      # elige el emulador Android o Chrome (web)
```

La URL del backend se define con `--dart-define=API_BASE_URL=http://<ip-del-backend>:5000` (emulador Android: `10.0.2.2`; celular físico: la IP de tu PC en la misma red Wi-Fi, que también debe figurar en `android/app/src/main/res/xml/network_security_config.xml`). Si no se indica, se usa el valor por defecto de `lib/core/api_client.dart`.

## 3. APK de publicación (release, sin cinta DEBUG)

```bash
# Opcional: firma propia. Crea android/key.properties (NO se versiona) con
#   storePassword=...  keyPassword=...  keyAlias=...  storeFile=/ruta/al/keystore.jks
# Sin ese archivo, el release se firma con la clave de debug (sirve para la demo).

flutter build apk --release --dart-define=API_BASE_URL=http://<ip-de-tu-pc>:5000
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`. La IP debe estar también en `android/app/src/main/res/xml/network_security_config.xml` (tráfico HTTP solo de desarrollo). Con backend HTTPS usa `--dart-define=ENV=prod --dart-define=API_BASE_URL=https://...`.

## 4. Variables útiles para la demo (video)

```bash
export JWT_ACCESS_TOKEN_EXPIRES_MINUTES=1   # para forzar la expiración del token en el video
export JWT_REFRESH_TOKEN_EXPIRES_DAYS=7
```

## 5. Diagramas y documentación ya incluidos

- `docs/diagrams/erd.svg` — modelo entidad-relación.
- `docs/diagrams/architecture.svg` — diagrama de arquitectura.
- `backend/openapi.yaml` — especificación Swagger/OpenAPI de los 12 endpoints.
- `backend/postman_collection.json` — colección de Postman para probar la API a mano.
