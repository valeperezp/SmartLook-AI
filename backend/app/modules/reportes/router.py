"""Endpoints HTTP del módulo reportes.

- CU15: /reportes/dashboard (y los endpoints de reservas que ya usaba la web).
- CU14: /reportes/generativo para pedir un reporte en lenguaje natural y exportarlo.
Todo filtrado por la empresa del usuario; el encargado solo ve su sucursal.
"""
import re
from datetime import datetime
from io import BytesIO

from fastapi import APIRouter, Depends, Query
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.reportes import exportador, generativo, schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.db.session import get_db

router = APIRouter(prefix="/reportes", tags=["reportes"])

admin_or_encargado = require_roles("administrador", "encargado_sucursal")
admin_only = require_roles("administrador")

_TIPOS = {
    "pdf": ("application/pdf", "pdf"),
    "excel": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"),
}


def _archivo(contenido: bytes, formato: str, base: str) -> StreamingResponse:
    media_type, extension = _TIPOS[formato]
    slug = re.sub(r"[^a-z0-9]+", "-", base.lower()).strip("-")[:40] or "reporte"
    nombre = f"{slug}-{datetime.now(ZONA_HORARIA_LOCAL).strftime('%Y%m%d-%H%M')}.{extension}"
    return StreamingResponse(
        BytesIO(contenido),
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{nombre}"'},
    )


# ---------------------------------------------------------------- CU15 dashboard

@router.get("/dashboard", response_model=schemas.Dashboard)
def dashboard(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    dias: int = Query(30, ge=1, le=365),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Indicadores y series del dashboard analítico en una sola respuesta."""
    efectiva = service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.dashboard(db, usuario.empresa_id, efectiva, dias, usuario.rol == "administrador")


@router.get("/resumen", response_model=schemas.ResumenReportes)
def resumen_general(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.resumen_general(db, usuario.empresa_id, sucursal_id=efectiva)


@router.get("/reservas-por-estado", response_model=list[schemas.ReservasPorEstado])
def reservas_por_estado(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.reservas_por_estado(db, usuario.empresa_id, sucursal_id=efectiva)


@router.get("/reservas-por-sucursal", response_model=list[schemas.ReservasPorSucursal])
def reservas_por_sucursal(db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    """Comparativa de reservas entre sucursales (solo admin)."""
    return service.reservas_por_sucursal(db, admin.empresa_id)


@router.get("/productos-mas-reservados", response_model=list[schemas.ProductoMasReservado])
def productos_mas_reservados(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    limit: int = Query(10, ge=1, le=50),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.productos_mas_reservados(db, usuario.empresa_id, sucursal_id=efectiva, limit=limit)


@router.get("/reservas-por-dia", response_model=list[schemas.ReservasPorDia])
def reservas_por_dia(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    dias: int = Query(14, ge=1, le=90),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.reservas_por_dia(db, usuario.empresa_id, sucursal_id=efectiva, dias=dias)


@router.get("/exportar/{formato}")
def exportar(
    formato: str,
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    dias: int = Query(30, ge=1, le=365),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Descarga el dashboard del período en PDF o Excel (formato: pdf | excel)."""
    formato = "excel" if formato in ("excel", "xlsx") else "pdf"
    datos, _ = service.contexto_reporte(db, usuario, sucursal_id, dias)
    titulo = "Reporte de ventas, reservas e inventario"
    generar = exportador.generar_pdf if formato == "pdf" else exportador.generar_excel
    return _archivo(generar(datos, titulo), formato, "reporte-smartlook")


# ---------------------------------------------------------------- CU14 generativo

@router.post("/generativo", response_model=schemas.ReporteGenerativoOut)
async def reporte_generativo(
    data: schemas.ReporteGenerativoRequest,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Redacta un reporte a pedido con IA (o por reglas si la IA no está disponible)."""
    # La llamada al modelo puede tardar: se hace fuera del event loop.
    return await run_in_threadpool(generativo.generar, db, usuario, data.solicitud, data.sucursal_id, data.dias)


@router.post("/generativo/exportar")
def exportar_generativo(
    data: schemas.ExportarGenerativoRequest,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Exporta el reporte redactado + las tablas con los datos reales del mismo período."""
    datos, _ = service.contexto_reporte(db, usuario, data.sucursal_id, data.periodo_dias)
    generar = exportador.generar_pdf if data.formato == "pdf" else exportador.generar_excel
    return _archivo(generar(datos, data.titulo, data.contenido), data.formato, data.titulo)
