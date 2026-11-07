"""Endpoints de las suscripciones de stock (CU16 — "Avísame cuando llegue")."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.suscripciones import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/suscripciones", tags=["suscripciones"])

solo_cliente = require_roles("cliente")


@router.post("", response_model=schemas.SuscripcionOut, status_code=201)
def suscribirse(data: schemas.SuscripcionCreate, db: Session = Depends(get_db), usuario: Usuario = Depends(solo_cliente)):
    """El cliente pide que le avisen cuando una prenda agotada vuelva a tener stock. Reenviar lo mismo no duplica."""
    return service.suscribir(db, usuario, data)


@router.get("/mias", response_model=list[schemas.SuscripcionOut])
def mis_suscripciones(db: Session = Depends(get_db), usuario: Usuario = Depends(solo_cliente)):
    """Todas las suscripciones del cliente (pendientes y ya notificadas)."""
    return service.mis_suscripciones(db, usuario)


@router.get("/mis-notificaciones", response_model=list[schemas.SuscripcionOut])
def mis_notificaciones(
    solo_nuevas: bool = Query(False, description="Solo los avisos que el cliente todavía no vio"),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(solo_cliente),
):
    """Los avisos del cliente: prendas que esperaba y que ya llegaron (`estado = notificado`)."""
    return service.mis_notificaciones(db, usuario, solo_nuevas)


@router.post("/marcar-vistas", response_model=schemas.MarcarVistasOut)
def marcar_vistas(db: Session = Depends(get_db), usuario: Usuario = Depends(solo_cliente)):
    """El cliente ya vio sus avisos nuevos (para no mostrarlos otra vez como nuevos)."""
    return {"marcadas": service.marcar_vistas(db, usuario)}
