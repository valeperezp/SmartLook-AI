"""Endpoints HTTP del módulo Reservas."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db
from app.modules.reservas import schemas, service

router = APIRouter(prefix="/reservas", tags=["reservas"])

cliente_only = require_roles("cliente", "administrador")
encargado_or_admin = require_roles("administrador", "encargado_sucursal")


# =========================================================================
# ENDPOINTS DEL CLIENTE
# =========================================================================

@router.post("", response_model=schemas.ReservaCompletaOut, status_code=201)
def crear_reserva(
    data: schemas.ReservaCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_only),
):
    """Crear una nueva reserva. El cliente se obtiene del token."""
    reserva = service.crear_reserva(db, data, cliente_id=usuario.id)
    return service.obtener_reserva(db, reserva.id, usuario.id)


@router.get("/mis-reservas", response_model=list[schemas.ReservaCompletaOut])
def listar_mis_reservas(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_only),
):
    """Lista las reservas del cliente autenticado."""
    return service.listar_mis_reservas(db, cliente_id=usuario.id)


# =========================================================================
# ENDPOINTS DEL ENCARGADO/ADMIN (deben ir ANTES de /{reserva_id})
# =========================================================================

@router.get("/mi-sucursal", response_model=list[schemas.ReservaCompletaOut])
def listar_mi_sucursal(
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Lista reservas de la sucursal del encargado autenticado."""
    if usuario.rol == "encargado_sucursal":
        if not usuario.sucursal_id:
            raise HTTPException(status_code=403, detail="El encargado no tiene sucursal asignada")
        return service.listar_reservas_mi_sucursal(db, usuario.sucursal_id)
    # Admin: si tiene sucursal_id filtrado, si no, todas
    if usuario.sucursal_id:
        return service.listar_reservas_por_sucursal(db, usuario.sucursal_id)
    return []


@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.ReservaCompletaOut])
def listar_por_sucursal(
    sucursal_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Lista reservas de una sucursal. El encargado solo puede ver la suya."""
    if usuario.rol == "encargado_sucursal" and usuario.sucursal_id != sucursal_id:
        raise HTTPException(status_code=403, detail="No tiene permisos para ver reservas de otra sucursal")
    return service.listar_reservas_por_sucursal(db, sucursal_id)


@router.get("/detalle/{reserva_id}", response_model=schemas.ReservaCompletaOut)
def obtener_detalle_encargado(
    reserva_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Obtiene el detalle de una reserva (encargado solo de su sucursal)."""
    sucursal_id = usuario.sucursal_id if usuario.rol == "encargado_sucursal" else None
    if sucursal_id is not None:
        reserva = service.obtener_reserva_por_sucursal(db, reserva_id, sucursal_id)
    else:
        reserva = service.obtener_reserva(db, reserva_id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return reserva


# =========================================================================
# ENDPOINTS CON PATH PARAM (van al final para evitar conflictos)
# =========================================================================

@router.get("/{reserva_id}", response_model=schemas.ReservaCompletaOut)
def obtener_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_only),
):
    """Obtiene el detalle de una reserva (solo del dueño)."""
    reserva = service.obtener_reserva(db, reserva_id, cliente_id=usuario.id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return reserva


@router.patch("/{reserva_id}/cancelar", response_model=schemas.ReservaCompletaOut)
def cancelar_reserva(
    reserva_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_only),
):
    """Cancela una reserva y devuelve el stock."""
    reserva = service.cancelar_reserva(db, reserva_id, cliente_id=usuario.id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return service.obtener_reserva(db, reserva.id, usuario.id)


@router.patch("/{reserva_id}/estado", response_model=schemas.ReservaCompletaOut)
def cambiar_estado(
    reserva_id: int,
    nuevo_estado: str,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Cambia el estado de una reserva con validaciones (encargado/admin)."""
    sucursal_id = usuario.sucursal_id if usuario.rol == "encargado_sucursal" else None
    reserva = service.cambiar_estado_con_validacion(db, reserva_id, nuevo_estado, sucursal_id)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return service.obtener_reserva(db, reserva.id)
