"""Endpoints HTTP del módulo Inventario (solo lectura para administrador)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.inventario import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/inventario", tags=["inventario"])
admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.InventarioOut], dependencies=[Depends(admin_only)])
def listar_inventario(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal"),
    producto_id: int | None = Query(None, description="Filtrar por producto"),
    categoria_id: int | None = Query(None, description="Filtrar por categoría de producto"),
    talla_id: int | None = Query(None, description="Filtrar por talla"),
    color_id: int | None = Query(None, description="Filtrar por color"),
    solo_disponibles: bool = Query(False, description="Mostrar solo con stock disponible"),
    solo_agotados: bool = Query(False, description="Mostrar solo productos agotados"),
    db: Session = Depends(get_db),
):
    """Consulta global de existencias de inventario con múltiples filtros."""
    return service.listar_inventario(
        db=db,
        sucursal_id=sucursal_id,
        producto_id=producto_id,
        categoria_id=categoria_id,
        talla_id=talla_id,
        color_id=color_id,
        solo_disponibles=solo_disponibles,
        solo_agotados=solo_agotados,
    )


@router.get("/resumen", response_model=schemas.ResumenInventario, dependencies=[Depends(admin_only)])
def obtener_resumen_global(db: Session = Depends(get_db)):
    """Resumen consolidado de indicadores globales de inventario."""
    return service.resumen_global(db)


@router.get("/alertas", response_model=list[schemas.AlertaStock], dependencies=[Depends(admin_only)])
def obtener_alertas_stock(db: Session = Depends(get_db)):
    """Listado de alertas por productos con stock bajo o agotados."""
    return service.alertas_stock_bajo(db)


@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.InventarioOut], dependencies=[Depends(admin_only)])
def inventario_por_sucursal(sucursal_id: int, db: Session = Depends(get_db)):
    """Consulta de inventario para una sucursal específica."""
    return service.inventario_por_sucursal(db, sucursal_id)


@router.get("/producto/{producto_id}", response_model=list[schemas.InventarioOut], dependencies=[Depends(admin_only)])
def inventario_por_producto(producto_id: int, db: Session = Depends(get_db)):
    """Consulta de distribución de stock de un producto en todas las sucursales."""
    return service.inventario_por_producto(db, producto_id)
