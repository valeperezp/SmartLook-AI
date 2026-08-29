# SmartLook-AI

Plataforma inteligente de comercio electrónico para una cadena de tiendas de ropa, con vestidores virtuales mediante realidad aumentada y funcionalidades de inteligencia artificial.

**Curso:** Sistemas II — Examen 1 (S2-2026)
**Docente:** MSc. Ing. Angélica Garzón Cuéllar
**Equipo:** 2 integrantes
**Duración:** 4 semanas (25/08/2026 – 22/09/2026)

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

## Cómo levantar el backend localmente

```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # En Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
uvicorn app.main:app --reload
```

Swagger interactivo en `http://localhost:8000/docs`.

## Frontend web (Angular)

```bash
cd frontend-web
npm install -g @angular/cli
ng new . --directory=. --routing --style=scss
```

Estructura sugerida por módulos: `catalogo/`, `disponibilidad/`, `reservas/`, `carrito/`, `checkout/`, `vestidor-ar/`, `perfil/`, `admin/` — reflejando los mismos dominios del backend.

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
