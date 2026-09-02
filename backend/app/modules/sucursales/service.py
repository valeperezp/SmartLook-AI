"""Lógica de negocio del módulo Sucursales."""
from sqlalchemy.orm import Session

from app.modules.sucursales import models, schemas


def listar_sucursales(db: Session) -> list[models.Sucursal]:
    return db.query(models.Sucursal).order_by(models.Sucursal.id).all()


def obtener_sucursal(db: Session, sucursal_id: int) -> models.Sucursal | None:
    return db.query(models.Sucursal).filter(models.Sucursal.id == sucursal_id).first()


def crear_sucursal(db: Session, data: schemas.SucursalCreate) -> models.Sucursal:
    sucursal = models.Sucursal(**data.model_dump())
    db.add(sucursal)
    db.commit()
    db.refresh(sucursal)
    return sucursal


def actualizar_sucursal(db: Session, sucursal_id: int, data: schemas.SucursalUpdate) -> models.Sucursal | None:
    sucursal = obtener_sucursal(db, sucursal_id)
    if not sucursal:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(sucursal, campo, valor)
    db.commit()
    db.refresh(sucursal)
    return sucursal


def eliminar_sucursal(db: Session, sucursal_id: int) -> models.Sucursal | None:
    sucursal = obtener_sucursal(db, sucursal_id)
    if not sucursal:
        return None
    sucursal.activa = False
    db.commit()
    db.refresh(sucursal)
    return sucursal
