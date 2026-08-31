"""Esquemas Pydantic (validación de entrada/salida) del módulo Catálogo."""
from pydantic import BaseModel, ConfigDict


class ProductoBase(BaseModel):
    nombre: str
    descripcion: str | None = None
    categoria: str | None = None
    talla: str | None = None
    color: str | None = None
    temporada: str | None = None
    precio: float


class ProductoCreate(ProductoBase):
    pass


class ProductoOut(ProductoBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
