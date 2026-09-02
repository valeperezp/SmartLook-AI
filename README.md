# SmartLook-AI

Plataforma inteligente de comercio electrónico para una cadena de tiendas de ropa, con vestidores virtuales mediante realidad aumentada y funcionalidades de inteligencia artificial.


## Stack tecnológico

| Componente        | Tecnología              |
|-------------------|--------------------------|
| Backend           | Python + FastAPI (arquitectura modular) |
| Frontend web      | Angular                  |
| App móvil         | Flutter + Dart           |
| Base de datos     | PostgreSQL               |
| IA                | Servicio/modelo vía API  |
| Metodología       | PUDS                     |
| Modelado          | UML 2.5+                 |
| Despliegue        | Nube (no localhost)      |

## Arquitectura: monolito modular

El backend está organizado **por dominio de negocio**, no por tipo técnico. Cada módulo en `backend/app/modules/` es autocontenido:

```
modules/<dominio>/
├── models.py    # Tablas SQLAlchemy de ese dominio
├── schemas.py   # Validación Pydantic (entrada/salida)
├── service.py   # Lógica de negocio, sin saber nada de HTTP
└── router.py    # Endpoints FastAPI, delega todo a service.py
```

**Módulos actuales:** `auth`, `usuarios`, `sucursales`, `catalogo`, `inventario`, `reservas`, `ventas`, `pagos`, `ia`, `reportes`.

`catalogo` y `reservas` ya están implementados de punta a punta como referencia — el resto tiene el mismo esqueleto listo para llenar.

`backend/app/shared/` tiene lo transversal (config, conexión a DB, seguridad, utilidades) — ningún módulo debe duplicar esto.

**¿Por qué así?**
- Cada dominio se puede desarrollar, probar y entender de forma aislada (ideal trabajando entre 2 personas sin pisarse).
- Si un módulo crece demasiado (ej. `ia` o `pagos`), se puede extraer a un microservicio aparte sin reescribir el resto — el acoplamiento entre módulos es mínimo y explícito (vía `shared/`).
- `main.py` solo ensambla routers, nunca contiene lógica de negocio.

Para agregar un módulo nuevo: copiar la carpeta de otro módulo, renombrar, y registrar su router en `main.py`.

## Estructura del repositorio

```
smartlook-ai/
├── backend/
│   └── app/
│       ├── modules/     # Un subdirectorio por dominio de negocio
│       └── shared/      # config, db, security, utils compartidos
├── frontend-web/         # Angular
├── mobile-app/            # Flutter
└── docs/                 # Documentación PUDS + UML (ver docs/README.md)
```

## Cómo levantar el proyecto

### Opción recomendada: Docker

Requiere tener [Docker Desktop](https://www.docker.com/products/docker-desktop/) instalado y corriendo.

1. Pedile a tu compañero de equipo el archivo `backend/.env` (tiene credenciales de la base de datos, no está en el repo — ver `backend/.env.example` para el formato). Colocalo en `backend/.env`.
2. Desde la raíz del proyecto:
   ```bash
   docker compose up -d
   ```
3. Listo:
   - Backend + Swagger: `http://localhost:8000/docs`
   - Frontend web: `http://localhost:4200`

Para parar todo: `docker compose down`. Para ver logs: `docker compose logs -f`. Si cambiás dependencias (`requirements.txt` o `package.json`), reconstruí con `docker compose up -d --build`.

El código fuente está montado como volumen, así que los cambios que hagas en `backend/app/` o `frontend-web/src/` se recargan solos (hot-reload), sin necesidad de reconstruir la imagen.

**Nota (Windows + Docker Desktop):** el hot-reload del backend (uvicorn) es confiable. El del frontend a veces no detecta cambios en archivos "core" del bundle (`app.config.ts`, `app.ts`, `main.ts`, `app.routes.ts`) — es un problema conocido de Vite con bind mounts en Windows. Si guardás uno de esos archivos y no ves el cambio reflejado, corré `docker compose restart frontend`. Los componentes de página sueltos (features/*) sí recargan solos sin problema.

### Opción manual (sin Docker)

**Backend:**
```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # En Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env       # completar con las credenciales reales
uvicorn app.main:app --reload
```
Swagger interactivo en `http://localhost:8000/docs`.

**Frontend:**
```bash
cd frontend-web
npm install
npm start
```
Queda en `http://localhost:4200`.

### Nota sobre la conexión a la base de datos (Supabase)

El `DATABASE_URL` de `backend/.env` **debe usar el connection string del "Session pooler"**, no el de "Conexión directa". El host de conexión directa (`db.<proyecto>.supabase.co`) es IPv6-only, y muchas redes/ISP en Bolivia no tienen IPv6, lo que causa el error `could not translate host name ... to address`.

Para conseguir el string correcto: Supabase Dashboard → tu proyecto → botón **"Connect"** → pestaña **"Session pooler"**. El host va a verse como `aws-0-<región>.pooler.supabase.com` y el usuario como `postgres.<project-ref>`.

Si la contraseña tiene caracteres especiales (`%`, `@`, etc.), hay que codificarlos como percent-encoding en la URL (por ejemplo `%` → `%25`).

## App móvil (Flutter)

```bash
cd mobile-app
flutter create .
```

## Flujo de trabajo en equipo (2 personas)

Al ser modular, cada quien puede "tomar" un dominio distinto sin pisarse:

- **Persona A:** backend (módulos core: auth, usuarios, catalogo, inventario, reservas)
- **Persona B:** frontend web (Angular) + módulos backend de ventas/pagos/ia + documentación UML

### Ramas y commits

- `main` → estable, lista para presentar
- `feature/<modulo>-<algo>` → ej. `feature/catalogo-filtros`, `feature/reservas-endpoint`

```
feat(catalogo): agregar filtro por temporada
fix(reservas): corregir cambio de estado
docs: actualizar diagrama de casos de uso
```

## Documentación académica

Ver [`docs/README.md`](docs/README.md).
