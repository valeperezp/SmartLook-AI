"""Endpoints HTTP del módulo Reservas."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.shared.db.session import get_db
from app.modules.reservas import schemas, service

router = APIRouter(prefix="/reservas", tags=["reservas"])


@router.post("", response_model=schemas.ReservaOut, status_code=201)
def crear_reserva(data: schemas.ReservaCreate, db: Session = Depends(get_db)):
    return service.crear_reserva(db, data)


@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.ReservaOut])
def listar_por_sucursal(sucursal_id: int, db: Session = Depends(get_db)):
    return service.listar_reservas_por_sucursal(db, sucursal_id)


@router.patch("/{reserva_id}/estado", response_model=schemas.ReservaOut)
def cambiar_estado(reserva_id: int, nuevo_estado: str, db: Session = Depends(get_db)):
    reserva = service.cambiar_estado(db, reserva_id, nuevo_estado)
    if not reserva:
        raise HTTPException(status_code=404, detail="Reserva no encontrada")
    return reserva
