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

@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.ReservaCompletaOut])
def listar_por_sucursal(
    sucursal_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Lista reservas de una sucursal (encargado/admin)."""
    return service.listar_reservas_por_sucursal(db, sucursal_id)


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


@router.patch("/{reserva_id}/estado", response_model=schemas.ReservaOut)
def cambiar_estado(
    reserva_id: int,
    nuevo_estado: str,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Cambia el estado de una reserva (encargado/admin)."""
    reserva = service.cambiar_estado(db, reserva_id, nuevo_estado)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return reserva
