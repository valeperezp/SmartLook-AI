"""Endpoints de transferencias de stock entre sucursales (CU19). Admin y encargados."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.inventario import service as inventario_service
from app.modules.inventario.schemas import InventarioOut
from app.modules.transferencias import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/transferencias", tags=["transferencias"])

admin_or_encargado = require_roles("administrador", "encargado_sucursal")


@router.get("", response_model=list[schemas.TransferenciaOut])
def listar(
    estado: schemas.EstadoTransferencia | None = Query(None),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    return [service.a_salida(usuario, t) for t in service.listar(db, usuario, estado)]


@router.get("/stock-origen", response_model=list[InventarioOut])
def stock_origen(
    sucursal_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    """Prendas con stock en una sucursal de la empresa, para armar una transferencia.

    El encargado no puede consultar el inventario de otras sucursales, pero sí
    necesita ver qué hay disponible para pedírselo.
    """
    return inventario_service.listar_inventario(
        db, usuario.empresa_id, sucursal_id=sucursal_id, solo_disponibles=True
    )


@router.get("/{transferencia_id}", response_model=schemas.TransferenciaOut)
def obtener(transferencia_id: int, db: Session = Depends(get_db), usuario: Usuario = Depends(admin_or_encargado)):
    return service.a_salida(usuario, service.obtener(db, usuario, transferencia_id))


@router.post("", response_model=schemas.TransferenciaOut, status_code=201)
def crear(
    data: schemas.TransferenciaCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    return service.a_salida(usuario, service.crear(db, usuario, data))


@router.post("/{transferencia_id}/{accion}", response_model=schemas.TransferenciaOut)
def ejecutar_accion(
    transferencia_id: int,
    accion: schemas.Accion,
    data: schemas.AccionRequest | None = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    """Avanza la transferencia: aprobar, rechazar, despachar, recibir o cancelar."""
    comentario = data.comentario if data else None
    return service.a_salida(usuario, service.ejecutar(db, usuario, transferencia_id, accion, comentario))
