"""Lógica de negocio del módulo Proveedores. Cada empresa tiene sus propios proveedores."""
from sqlalchemy.orm import Session

from app.modules.proveedores import models, schemas


def listar_proveedores(db: Session, empresa_id: int) -> list[models.Proveedor]:
    return (
        db.query(models.Proveedor)
        .filter(models.Proveedor.empresa_id == empresa_id)
        .order_by(models.Proveedor.id)
        .all()
    )


def obtener_proveedor(db: Session, proveedor_id: int, empresa_id: int) -> models.Proveedor | None:
    return (
        db.query(models.Proveedor)
        .filter(models.Proveedor.id == proveedor_id, models.Proveedor.empresa_id == empresa_id)
        .first()
    )


def crear_proveedor(db: Session, data: schemas.ProveedorCreate, empresa_id: int) -> models.Proveedor:
    proveedor = models.Proveedor(**data.model_dump(), empresa_id=empresa_id)
    db.add(proveedor)
    db.commit()
    db.refresh(proveedor)
    return proveedor


def actualizar_proveedor(
    db: Session, proveedor_id: int, data: schemas.ProveedorUpdate, empresa_id: int
) -> models.Proveedor | None:
    proveedor = obtener_proveedor(db, proveedor_id, empresa_id)
    if not proveedor:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(proveedor, campo, valor)
    db.commit()
    db.refresh(proveedor)
    return proveedor


def eliminar_proveedor(db: Session, proveedor_id: int, empresa_id: int) -> models.Proveedor | None:
    proveedor = obtener_proveedor(db, proveedor_id, empresa_id)
    if not proveedor:
        return None
    proveedor.activo = False
    db.commit()
    db.refresh(proveedor)
    return proveedor
