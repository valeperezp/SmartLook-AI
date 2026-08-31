"""Lógica de negocio del módulo Catálogo (independiente de FastAPI/HTTP)."""
from sqlalchemy.orm import Session

from app.modules.catalogo import models, schemas


def listar_productos(db: Session, categoria: str | None = None) -> list[models.Producto]:
    query = db.query(models.Producto)
    if categoria:
        query = query.filter(models.Producto.categoria == categoria)
    return query.all()


def obtener_producto(db: Session, producto_id: int) -> models.Producto | None:
    return db.query(models.Producto).filter(models.Producto.id == producto_id).first()


def crear_producto(db: Session, data: schemas.ProductoCreate) -> models.Producto:
    producto = models.Producto(**data.model_dump())
    db.add(producto)
    db.commit()
    db.refresh(producto)
    return producto
