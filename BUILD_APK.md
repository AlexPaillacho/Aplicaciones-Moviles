# APK automático con GitHub Actions

Cada vez que **publicas un Release** en GitHub, el workflow
`.github/workflows/release-apk.yml` compila la app y adjunta el
`speak-english-vX.Y.Z.apk` al propio Release.

## 1. Subir el workflow al repositorio

El archivo debe quedar en la **raíz del repositorio** (junto a `pubspec.yaml`):

```
.github/workflows/release-apk.yml
BUILD_APK.md
```

```bash
git add .github/workflows/release-apk.yml BUILD_APK.md
git commit -m "Agrega workflow para generar el APK en cada release"
git push
```

> Si tu `pubspec.yaml` está dentro de una subcarpeta (por ejemplo `speak_english/`),
> agrega bajo `jobs.apk` el bloque
> `defaults: { run: { working-directory: speak_english } }` y cambia las rutas
> `android/key.properties` y `build/app/...` en el workflow por las de esa carpeta.

## 2. Crear el Release

En GitHub: **Releases → Draft a new release**

1. *Choose a tag* → escribe `v1.0.0` → *Create new tag on publish*.
2. Título, por ejemplo `Versión 1.0.0`.
3. **Publish release**.

(O por consola: `gh release create v1.0.0 --title "Versión 1.0.0" --notes "Primera entrega"`.)

## 3. Descargar el APK

- Pestaña **Actions → Release APK**: verás la ejecución (tarda unos minutos).
- Al terminar, el APK aparece en **Releases → v1.0.0 → Assets** y también como
  artefacto `apk` de la ejecución.
- Cópialo al celular e instálalo (permite "instalar apps de orígenes desconocidos").

Con **Actions → Release APK → Run workflow** puedes generarlo sin crear un Release
(solo queda como artefacto de la ejecución).

## Dirección del backend dentro del APK

<<<<<<< HEAD
Por defecto el APK apunta a `http://192.168.1.16:5000` (la IP de tu PC en el wifi),
=======
Por defecto el APK apunta a `http://192.168.101.24:5000` (la IP de tu PC en el wifi),
>>>>>>> 441e3df4079ae09a8bd0dcbb64073aefcc0b32f1
que es la única dirección HTTP permitida en `android/.../network_security_config.xml`.
Por eso el celular debe estar en el mismo wifi que tu PC con Flask corriendo.

Para usar otra dirección crea la variable de repositorio `API_BASE_URL`
(*Settings → Secrets and variables → Actions → Variables*) y agrégala también a
`network_security_config.xml` si es HTTP.

## Firma (opcional)

Sin configurar nada, el APK se firma con la clave de debug y se instala igual.
Si quieres firmarlo con tu propio keystore, crea estos secrets
(*Settings → Secrets and variables → Actions*):

| Secret | Contenido |
|---|---|
| `KEYSTORE_BASE64` | el `.jks` codificado en base64 |
| `KEYSTORE_PASSWORD` | contraseña del keystore |
| `KEY_PASSWORD` | contraseña de la clave |
| `KEY_ALIAS` | alias de la clave (ej. `upload`) |

Crear el keystore y subir los secrets (PowerShell, con GitHub CLI):

```powershell
keytool -genkey -v -keystore C:\secure\speak-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\speak-upload.jks")) | gh secret set KEYSTORE_BASE64
gh secret set KEYSTORE_PASSWORD
gh secret set KEY_PASSWORD
gh secret set KEY_ALIAS --body upload
```

Nunca subas el `.jks` ni `key.properties` al repositorio (ya están en `.gitignore`).

## Si el workflow falla

- **flutter analyze**: solo los *errores* detienen el build; léelos en el log.
- **flutter test**: corrige el test que falle o revisa el log.
- **Versión de Flutter**: el workflow usa `3.44.5` (la misma que el ejemplo del ingeniero);
  tu `pubspec.yaml` exige Dart `^3.12.2`. Si el log dice que la versión del SDK no
  coincide, cambia `flutter-version` en el workflow.
