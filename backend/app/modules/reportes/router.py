"""Endpoints HTTP del módulo reportes (CU13 — Consultar reportes y dashboards)."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.reportes import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/reportes", tags=["reportes"])

admin_or_encargado = require_roles("administrador", "encargado_sucursal")


def _sucursal_efectiva(usuario: Usuario, sucursal_id: int | None) -> int | None:
    """Un encargado solo puede ver reportes de su propia sucursal; el admin puede ver todo o filtrar."""
    if usuario.rol == "encargado_sucursal":
        if not usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El encargado de sucursal no tiene una sucursal asignada.",
            )
        if sucursal_id is not None and sucursal_id != usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para ver reportes de otra sucursal.",
            )
        return usuario.sucursal_id
    return sucursal_id


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
