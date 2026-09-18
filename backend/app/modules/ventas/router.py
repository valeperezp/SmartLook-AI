"""Endpoints HTTP del módulo Ventas."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db
from app.modules.ventas import schemas, service

router = APIRouter(prefix="/ventas", tags=["ventas"])

cajero_or_admin = require_roles("cajero", "administrador", "encargado_sucursal")
cliente_or_admin = require_roles("cliente", "administrador")


@router.post("", response_model=schemas.VentaOut, status_code=201)
def crear_venta_presencial(
    data: schemas.VentaPresencialCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cajero_or_admin),
):
    """Registra una venta presencial. El cajero_id se obtiene del token."""
    # Si es cajero, validar que solo venda en su sucursal
    if usuario.rol == "cajero" and usuario.sucursal_id != data.sucursal_id:
        raise HTTPException(status_code=403, detail="El cajero solo puede vender en su sucursal asignada")
    return service.crear_venta_presencial(db, data, cajero_id=usuario.id)


@router.post("/online", response_model=schemas.VentaOut, status_code=201)
def crear_venta_online(
    data: schemas.VentaOnlineCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Registra una venta online para el cliente autenticado."""
    return service.crear_venta_online(db, data, cliente_id=usuario.id)


@router.get("/mis-compras", response_model=list[schemas.VentaOut])
def listar_mis_compras(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Lista las compras online del cliente autenticado."""
    return service.listar_mis_compras(db, cliente_id=usuario.id)


@router.get("/{venta_id}", response_model=schemas.VentaOut)
def obtener_venta(
    venta_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cajero_or_admin),
):
    """Obtiene el detalle de una venta."""
    venta = service.obtener_venta(db, venta_id)
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")
    return venta


@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.VentaOut])
def listar_por_sucursal(
    sucursal_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cajero_or_admin),
):
    """Lista las ventas de una sucursal."""
    if usuario.rol == "cajero" and usuario.sucursal_id != sucursal_id:
        raise HTTPException(status_code=403, detail="No tiene permisos para ver ventas de otra sucursal")
    return service.listar_ventas_por_sucursal(db, sucursal_id)


@router.get("", response_model=list[schemas.VentaOut])
def listar_todas(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("administrador")),
):
    """Lista todas las ventas (solo admin)."""
    return service.listar_todas_ventas(db)
