# Despliegue del backend en Render (plan gratis)

El frontend está en Vercel (`https://smart-look-ai.vercel.app`) y la base en Supabase. El backend se
despliega en Render con el `Dockerfile` de `backend/` y la configuración de `render.yaml` (raíz del repo).

## 1. Crear el servicio

1. Entrar a <https://render.com> → **Get Started** → registrarse con **GitHub**.
2. **New +** → **Blueprint** → conectar el repositorio `valeperezp/SmartLook-AI`.
3. Render lee `render.yaml` y muestra el servicio `smartlook-ai-api` (plan Free). Pide completar las
   variables marcadas como secretas. Copiarlas de `backend/.env`:

| Variable | De dónde sale |
|---|---|
| `DATABASE_URL` | La de **Supabase** en `backend/.env` (la que contiene `pooler.supabase.com`) |
| `SUPABASE_URL` | `backend/.env` |
| `SUPABASE_SERVICE_ROLE_KEY` | `backend/.env` |
| `STRIPE_SECRET_KEY` | `backend/.env` |
| `REPLICATE_API_TOKEN` | `backend/.env` |

`SECRET_KEY` la genera Render sola. `CORS_ORIGINS`, `ENVIRONMENT` y el resto ya vienen en `render.yaml`.
La URL pública (`RENDER_EXTERNAL_URL`) la define Render y el backend la usa para los enlaces de archivos.

4. **Apply**. La primera construcción tarda varios minutos (librerías de Machine Learning).

## 2. Comprobar

- `https://smartlook-ai-api.onrender.com/health` → `{"status":"healthy"}`
  (si Render asignó otra URL, usar esa).
- `https://smartlook-ai-api.onrender.com/docs` → documentación de la API.

## 3. Apuntar la web y la app al backend

Si la URL final es distinta de `https://smartlook-ai-api.onrender.com`, cambiarla en:

- `frontend-web/src/environments/environment.prod.ts` → `apiUrl`
- `frontend-web/ngsw-config.json` → URLs de caché offline
- `mobile-app/lib/core/config/env.dart` → URL de producción

Vercel vuelve a publicar la web sola al subir el cambio a `main`. La app Android hay que recompilarla.

## Limitaciones del plan gratis

- **Se duerme** tras 15 minutos sin uso y tarda ~1 minuto en despertar. Antes de una presentación,
  abrir `/health` unos minutos antes.
- **512 MB de memoria**: alcanza (el entrenamiento de ML llega a ~230 MB en las pruebas).
- **Sin disco persistente**: los QR de sucursales y los comprobantes de pago subidos se pierden cuando el
  servicio se reinicia o se duerme. Las fotos de productos (Supabase Storage) y los modelos de ML (base de
  datos) no se pierden.
