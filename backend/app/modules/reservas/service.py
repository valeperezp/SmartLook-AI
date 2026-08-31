"""Lógica de negocio del módulo Reservas."""
from sqlalchemy.orm import Session

from app.modules.reservas import models, schemas


def crear_reserva(db: Session, data: schemas.ReservaCreate) -> models.Reserva:
    # Nota: la relación con las prendas seleccionadas (producto_ids) se modela
    # con una tabla intermedia reserva_producto cuando se implemente por completo.
    reserva = models.Reserva(
        cliente_id=data.cliente_id,
        sucursal_id=data.sucursal_id,
        horario_aproximado=data.horario_aproximado,
    )
    db.add(reserva)
    db.commit()
    db.refresh(reserva)
    return reserva


def listar_reservas_por_sucursal(db: Session, sucursal_id: int) -> list[models.Reserva]:
    return db.query(models.Reserva).filter(models.Reserva.sucursal_id == sucursal_id).all()


def cambiar_estado(db: Session, reserva_id: int, nuevo_estado: str) -> models.Reserva | None:
    reserva = db.query(models.Reserva).filter(models.Reserva.id == reserva_id).first()
    if reserva:
        reserva.estado = nuevo_estado
        db.commit()
        db.refresh(reserva)
    return reserva
