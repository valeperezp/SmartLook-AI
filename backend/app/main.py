"""
SmartLook-AI — Punto de entrada del backend (FastAPI).

Arquitectura modular: cada dominio de negocio vive en app/modules/<dominio>/
con su propio models.py, schemas.py, service.py y router.py.
Este archivo solo ensambla los routers — no debe crecer con lógica de negocio.
"""
import asyncio
import logging
import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.shared.core.config import settings
from app.shared.db.session import engine, Base

from app.modules.catalogo.router import router as catalogo_router
from app.modules.reservas.router import router as reservas_router
from app.modules.auth.router import router as auth_router
from app.modules.usuarios.router import router as usuarios_router
from app.modules.sucursales.router import router as sucursales_router
from app.modules.proveedores.router import router as proveedores_router
from app.modules.inventario.router import router as inventario_router
from app.modules.ventas.router import router as ventas_router
from app.modules.pagos.router import router as pagos_router
from app.modules.ia.router import router as ia_router
from app.modules.reportes.router import router as reportes_router
from app.modules.promociones.router import router as promociones_router
from app.modules.vestidor.router import router as vestidor_router
from app.modules.empresas.router import empresas_router, mi_empresa_router, planes_router
from app.modules.transferencias.router import router as transferencias_router
from app.modules.analitica_ml.router import router as analitica_router
from app.modules.bitacora.router import router as bitacora_router
from app.modules.sync.router import router as sync_router
from app.modules.fidelizacion.router import router as fidelizacion_router

import app.modules.bitacora.models
import app.modules.sync.models
import app.modules.fidelizacion.models
import app.modules.analitica_ml.models
import app.modules.reportes.models
import app.modules.empresas.models
import app.modules.transferencias.models
import app.modules.usuarios.models
import app.modules.sucursales.models
import app.modules.proveedores.models
import app.modules.catalogo.models
import app.modules.reservas.models
import app.modules.inventario.models
import app.modules.ia.models
import app.modules.ventas.models
import app.modules.pagos.models
import app.modules.promociones.models
import app.modules.vestidor.models


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Crear tablas en PostgreSQL/Supabase al iniciar si no existen
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="SmartLook-AI API",
    description="API para la plataforma inteligente de comercio electrónico SmartLook-AI",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

os.makedirs(f"{settings.uploads_dir}/qr", exist_ok=True)
os.makedirs(f"{settings.uploads_dir}/comprobantes", exist_ok=True)

app.mount("/uploads", StaticFiles(directory=settings.uploads_dir), name="uploads")

# Registro de routers — un dominio, un router, un prefijo
app.include_router(auth_router)
app.include_router(empresas_router)
app.include_router(planes_router)
app.include_router(mi_empresa_router)
app.include_router(bitacora_router)
app.include_router(usuarios_router)
app.include_router(sucursales_router)
app.include_router(proveedores_router)
app.include_router(catalogo_router)
app.include_router(inventario_router)
app.include_router(transferencias_router)
app.include_router(reservas_router)
app.include_router(ventas_router)
app.include_router(pagos_router)
app.include_router(ia_router)
app.include_router(reportes_router)
app.include_router(analitica_router)
app.include_router(promociones_router)
app.include_router(vestidor_router)
app.include_router(sync_router)
app.include_router(fidelizacion_router)


@app.get("/", tags=["health"])
def root():
    return {"status": "ok", "service": "SmartLook-AI API"}


def _ping_db() -> None:
    with engine.connect() as conn:
        conn.execute(text("SELECT 1"))


@app.get("/health", tags=["health"])
async def health_check():
    # Si la BD no responde en 5 s (o falla) el servicio no esta sano: 503 en vez de un 200 engañoso.
    try:
        await asyncio.wait_for(run_in_threadpool(_ping_db), timeout=5.0)
    except Exception as exc:
        logging.getLogger(__name__).error("Health check: la base de datos no responde: %r", exc)
        return JSONResponse(status_code=503, content={"status": "unhealthy", "database": "unavailable"})
    return {"status": "healthy"}
