"""Endpoints HTTP del módulo reportes (CU13 — Consultar reportes y dashboards)."""
from datetime import datetime
from io import BytesIO

from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.reportes import exportador, schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.db.session import get_db

router = APIRouter(prefix="/reportes", tags=["reportes"])

admin_or_encargado = require_roles("administrador", "encargado_sucursal")

_sucursal_efectiva = service.sucursal_efectiva


@router.get("/resumen", response_model=schemas.ResumenReportes)
def resumen_general(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Resumen general del dashboard: reservas, estados e inventario."""
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    return service.resumen_general(db, sucursal_id=efectiva)


@router.get("/reservas-por-estado", response_model=list[schemas.ReservasPorEstado])
def reservas_por_estado(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    return service.reservas_por_estado(db, sucursal_id=efectiva)


@router.get("/reservas-por-sucursal", response_model=list[schemas.ReservasPorSucursal], dependencies=[Depends(require_roles("administrador"))])
def reservas_por_sucursal(db: Session = Depends(get_db)):
    """Comparativa de reservas entre sucursales (solo admin)."""
    return service.reservas_por_sucursal(db)


@router.get("/productos-mas-reservados", response_model=list[schemas.ProductoMasReservado])
def productos_mas_reservados(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    limit: int = Query(10, ge=1, le=50),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    return service.productos_mas_reservados(db, sucursal_id=efectiva, limit=limit)


@router.get("/reservas-por-dia", response_model=list[schemas.ReservasPorDia])
def reservas_por_dia(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    dias: int = Query(14, ge=1, le=90),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    return service.reservas_por_dia(db, sucursal_id=efectiva, dias=dias)


_nombre_sucursal = service.nombre_sucursal


@router.get("/exportar/pdf")
def exportar_pdf(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Descarga el reporte actual (resumen, estados, ranking y series) en PDF."""
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    contenido = exportador.generar_pdf(
        db, efectiva, _nombre_sucursal(db, efectiva), usuario.rol == "administrador"
    )
    nombre_archivo = f"reporte-smartlook-{datetime.now(ZONA_HORARIA_LOCAL).strftime('%Y%m%d-%H%M')}.pdf"
    return StreamingResponse(
        BytesIO(contenido),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nombre_archivo}"'},
    )


@router.get("/exportar/excel")
def exportar_excel(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Descarga el reporte actual (resumen, estados, ranking y series) en Excel (.xlsx)."""
    efectiva = _sucursal_efectiva(usuario, sucursal_id)
    contenido = exportador.generar_excel(
        db, efectiva, _nombre_sucursal(db, efectiva), usuario.rol == "administrador"
    )
    nombre_archivo = f"reporte-smartlook-{datetime.now(ZONA_HORARIA_LOCAL).strftime('%Y%m%d-%H%M')}.xlsx"
    return StreamingResponse(
        BytesIO(contenido),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{nombre_archivo}"'},
    )
