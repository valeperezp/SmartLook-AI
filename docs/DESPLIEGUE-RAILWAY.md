# Despliegue del backend en Railway

El frontend está en Vercel (`https://smartlook-ai.vercel.app`) y la base en Supabase. La web y la app
Android ya apuntan a `https://smartlook-ai-production.up.railway.app`, así que conviene recrear el
servicio con **ese mismo dominio**: así no hay que cambiar nada en el front ni en la app.

## 1. Crear el servicio

1. Entrar a <https://railway.com> con la cuenta del proyecto → **New Project** → **Deploy from GitHub repo**
   → elegir `valeperezp/SmartLook-AI`.
2. En el servicio creado → **Settings**:
   - **Root Directory**: `backend` (ahí están el `Dockerfile` y `railway.json`).
   - **Branch**: `main`.
3. Railway detecta el `Dockerfile` solo. El healthcheck usa `/health` (ya configurado en `railway.json`).

## 2. Variables de entorno (Settings → Variables)

Copiar los valores de `backend/.env` (nunca subir ese archivo al repo). En el editor **Raw** de Railway se
pueden pegar todas juntas con el formato `NOMBRE=valor`.

| Variable | Valor |
|---|---|
| `DATABASE_URL` | La de **Supabase** de `backend/.env` (la que empieza con `postgresql://postgres.…pooler.supabase.com`) |
| `SECRET_KEY` | Una clave larga y aleatoria. Generarla con: `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `ALGORITHM` | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `60` |
| `ENVIRONMENT` | `production` |
| `CORS_ORIGINS` | `https://smartlook-ai.vercel.app` (agregar otras URLs separadas por coma si hace falta) |
| `UPLOADS_BASE_URL` | `https://smartlook-ai-production.up.railway.app` |
| `SUPABASE_URL` | De `backend/.env` |
| `SUPABASE_SERVICE_ROLE_KEY` | De `backend/.env` |
| `STRIPE_SECRET_KEY` | De `backend/.env` (clave de prueba `sk_test_…`) |
| `REPLICATE_API_TOKEN` | De `backend/.env` (vestidor virtual) |
| `VESTIDOR_MAX_POR_USUARIO_DIA` | `5` |
| `GEMINI_API_KEY`, `HF_TOKEN`, `AI_API_KEY` | De `backend/.env`, si se usan |

No hace falta `PORT`: Railway lo define solo y el `Dockerfile` lo usa.

La configuración del chatbot y del reporte con IA (proveedor, modelo y clave) se guarda en la base, en la
pantalla **Asistente IA** del administrador, así que funciona igual en Railway sin variables extra.

## 3. Dominio

**Settings → Networking → Generate Domain** (o **Custom Domain**) y usar
`smartlook-ai-production.up.railway.app`. Si ese nombre ya no está disponible, usar el que dé Railway y
actualizarlo en:

- `frontend-web/src/environments/environment.prod.ts` → `apiUrl`
- `frontend-web/ngsw-config.json` → las URLs de caché offline
- `mobile-app/lib/core/config/env.dart` → URL de producción
- La variable `UPLOADS_BASE_URL` de Railway

## 4. Archivos subidos (recomendado)

Los QR de las sucursales y los comprobantes de pago se guardan en disco (`/app/uploads`). En Railway el
disco se borra en cada despliegue, así que conviene **agregar un Volume** (botón **+ New → Volume**) montado
en `/app/uploads`. Las fotos de productos van a Supabase Storage y los modelos de ML se guardan en la base,
así que esos no se pierden.

## 5. Comprobar

- `https://smartlook-ai-production.up.railway.app/health` → `{"status":"healthy"}`
- `https://smartlook-ai-production.up.railway.app/docs` → documentación de la API
- Entrar a `https://smartlook-ai.vercel.app` e iniciar sesión.

## Migraciones

La base de Supabase ya está migrada. Si en el futuro hay una migración nueva, se puede correr desde la
pestaña **Shell** del servicio en Railway:

```bash
python -m migraciones.m002_alineacion_documento --simular
python -m migraciones.m002_alineacion_documento
```
