"""Lógica de negocio del módulo Promociones (CU12)."""
from datetime import date
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.promociones import models, schemas


def listar_promociones(db: Session, solo_activas: bool = False) -> list[models.Promocion]:
    query = (
        db.query(models.Promocion)
        .options(joinedload(models.Promocion.productos).joinedload(models.PromocionProducto.producto))
    )
    if solo_activas:
        query = query.filter(models.Promocion.activo.is_(True))
    return query.order_by(models.Promocion.id.desc()).all()


def obtener_promocion(db: Session, promocion_id: int) -> models.Promocion | None:
    return (
        db.query(models.Promocion)
        .options(joinedload(models.Promocion.productos).joinedload(models.PromocionProducto.producto))
        .filter(models.Promocion.id == promocion_id)
        .first()
    )


def _validar_fechas(fecha_inicio: date, fecha_fin: date) -> None:
    if fecha_fin < fecha_inicio:
        raise HTTPException(status_code=400, detail="La fecha de fin no puede ser anterior a la de inicio")


def crear_promocion(db: Session, data: schemas.PromocionCreate) -> models.Promocion:
    _validar_fechas(data.fecha_inicio, data.fecha_fin)

    promocion = models.Promocion(
        nombre=data.nombre,
        descripcion=data.descripcion,
        tipo=data.tipo,
        valor=data.valor,
        fecha_inicio=data.fecha_inicio,
        fecha_fin=data.fecha_fin,
        activo=True,
    )
    db.add(promocion)
    db.flush()

    for producto_id in data.producto_ids:
        db.add(models.PromocionProducto(promocion_id=promocion.id, producto_id=producto_id))

    db.commit()
    db.refresh(promocion)
    return obtener_promocion(db, promocion.id)


def actualizar_promocion(db: Session, promocion_id: int, data: schemas.PromocionUpdate) -> models.Promocion | None:
    promocion = obtener_promocion(db, promocion_id)
    if not promocion:
        return None

    datos = data.model_dump(exclude_unset=True)

    # Validar fechas si se actualizan
    fecha_inicio = datos.get("fecha_inicio", promocion.fecha_inicio)
    fecha_fin = datos.get("fecha_fin", promocion.fecha_fin)
    _validar_fechas(fecha_inicio, fecha_fin)

    for campo, valor in datos.items():
        setattr(promocion, campo, valor)

    db.commit()
    db.refresh(promocion)
    return obtener_promocion(db, promocion_id)


def eliminar_promocion(db: Session, promocion_id: int) -> models.Promocion | None:
    promocion = obtener_promocion(db, promocion_id)
    if not promocion:
        return None
    promocion.activo = False
    db.commit()
    db.refresh(promocion)
    return promocion


def reactivar_promocion(db: Session, promocion_id: int) -> models.Promocion | None:
    promocion = obtener_promocion(db, promocion_id)
    if not promocion:
        return None
    promocion.activo = True
    db.commit()
    db.refresh(promocion)
    return promocion


def actualizar_productos(db: Session, promocion_id: int, data: schemas.PromocionProductosUpdate) -> models.Promocion | None:
    promocion = obtener_promocion(db, promocion_id)
    if not promocion:
        return None

    # Eliminar asociaciones actuales
    db.query(models.PromocionProducto).filter(models.PromocionProducto.promocion_id == promocion_id).delete()

    # Crear nuevas
    for producto_id in data.producto_ids:
        db.add(models.PromocionProducto(promocion_id=promocion_id, producto_id=producto_id))

    db.commit()
    db.refresh(promocion)
    return obtener_promocion(db, promocion_id)
