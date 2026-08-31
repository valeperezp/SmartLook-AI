"""
SmartLook-AI — Punto de entrada del backend (FastAPI).

Arquitectura modular: cada dominio de negocio vive en app/modules/<dominio>/
con su propio models.py, schemas.py, service.py y router.py.
Este archivo solo ensambla los routers — no debe crecer con lógica de negocio.
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.modules.catalogo.router import router as catalogo_router
from app.modules.reservas.router import router as reservas_router
from app.modules.auth.router import router as auth_router
from app.modules.usuarios.router import router as usuarios_router
from app.modules.sucursales.router import router as sucursales_router
from app.modules.inventario.router import router as inventario_router
from app.modules.ventas.router import router as ventas_router
from app.modules.pagos.router import router as pagos_router
from app.modules.ia.router import router as ia_router
from app.modules.reportes.router import router as reportes_router

from contextlib import asynccontextmanager
from app.shared.db.session import engine, Base
import app.modules.usuarios.models
import app.modules.sucursales.models
import app.modules.catalogo.models
import app.modules.reservas.models


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
    allow_origins=["*"],  # restringir en producción
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Registro de routers — un dominio, un router, un prefijo
app.include_router(auth_router)
app.include_router(usuarios_router)
app.include_router(sucursales_router)
app.include_router(catalogo_router)
app.include_router(inventario_router)
app.include_router(reservas_router)
app.include_router(ventas_router)
app.include_router(pagos_router)
app.include_router(ia_router)
app.include_router(reportes_router)


@app.get("/", tags=["health"])
def root():
    return {"status": "ok", "service": "SmartLook-AI API"}


@app.get("/health", tags=["health"])
def health_check():
    return {"status": "healthy"}
