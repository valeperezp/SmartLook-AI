# SmartLook-AI — App Móvil (Flutter)

Generar el proyecto (requiere Flutter SDK):

```bash
cd mobile-app
flutter create .
```

Pantallas sugeridas: `catalogo/`, `disponibilidad/`, `vestidor_ar/`, `reservas/`, `carrito_checkout/`, `perfil_historial/`.

## Compilar el APK

Requisitos: Flutter SDK >= 3.44.0 y Android SDK (Flutter genera `local.properties` y el wrapper de Gradle).

```bash
cd mobile-app
flutter pub get
flutter build apk --debug     # funciona siempre
flutter build apk --release   # firma real si hay keystore; si no, firma de debug
```

### Firma del APK release (opcional)

Sin `android/key.properties` el release se firma con la clave de **debug**. Gradle muestra un aviso (`WARNING: ...`), pero solo es visible con `flutter build apk --release -v`; sin `-v` el build termina bien y firma con debug sin informar del fallback. Sirve para probar, no para publicar en Play Store.

Para firmar con tu propia clave, genera un keystore (`keytool` viene con el JDK; con Android Studio está en `<carpeta de Android Studio>\jbr\bin\keytool.exe`):

```bash
keytool -genkey -v -keystore smartlook-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias smartlook
```

Guárdalo en `mobile-app/android/` y crea `mobile-app/android/key.properties` con estas 4 claves:

```properties
storePassword=<contraseña del keystore>
keyPassword=<contraseña de la clave>
keyAlias=smartlook
storeFile=smartlook-release-key.jks
```

`storeFile` es relativo a `mobile-app/android/`. Si falta una de las 4 claves o el archivo no existe, se usa la firma de debug y se avisa.

**No subas `key.properties` ni el `.jks` a git** (ya están en `android/.gitignore`) y guarda una copia de seguridad del `.jks`: si lo pierdes no podrás publicar actualizaciones firmadas con la misma clave.
