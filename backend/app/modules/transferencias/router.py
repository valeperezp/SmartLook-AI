"""Endpoints de transferencias de stock entre sucursales (CU19). Admin y encargados."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.empresas import service as empresas_service
from app.modules.inventario import service as inventario_service
from app.modules.inventario.schemas import InventarioOut
from app.modules.transferencias import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/transferencias", tags=["transferencias"])

_admin_or_encargado = require_roles("administrador", "encargado_sucursal")


def admin_or_encargado(
    usuario: Usuario = Depends(_admin_or_encargado), db: Session = Depends(get_db)
) -> Usuario:
    """Además del rol, el plan de la empresa tiene que incluir transferencias (RF-05)."""
    empresas_service.requiere_funcionalidad(db, usuario.empresa_id, "transferencias")
    return usuario


@router.get("", response_model=list[schemas.TransferenciaOut])
def listar(
    estado: schemas.EstadoTransferencia | None = Query(None),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    return [service.a_salida(usuario, t) for t in service.listar(db, usuario, estado)]


@router.get("/disponibilidad")
def disponibilidad(
    producto_id: int,
    talla_id: int | None = None,
    color_id: int | None = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(admin_or_encargado),
):
    """CU19 paso 2: sucursales de la empresa que tienen existencia de la prenda buscada.

    Lista vacía = "No hay existencia en otras sucursales" (2a).
    """
    return service.disponibilidad(db, usuario, producto_id, talla_id, color_id)


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
    """Avanza la transferencia: enviar, rechazar, recibir (confirmar recepción) o cancelar."""
    comentario = data.comentario if data else None
    recibidas = {r.item_id: r.cantidad_recibida for r in data.recibidas} if data else {}
    return service.a_salida(
        usuario, service.ejecutar(db, usuario, transferencia_id, accion, comentario, recibidas)
    )
