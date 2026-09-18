"""Esquemas Pydantic del módulo Promociones."""
from datetime import date
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field


TipoPromocion = Literal["porcentaje", "monto_fijo"]


class PromocionProductoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    producto_id: int
    nombre_producto: str = ""
    precio_producto: float = 0.0


class PromocionCreate(BaseModel):
    nombre: str = Field(..., min_length=1, max_length=150)
    descripcion: str | None = None
    tipo: TipoPromocion
    valor: float = Field(..., gt=0)
    fecha_inicio: date
    fecha_fin: date
    producto_ids: list[int] = []


class PromocionUpdate(BaseModel):
    nombre: str | None = None
    descripcion: str | None = None
    tipo: TipoPromocion | None = None
    valor: float | None = None
    fecha_inicio: date | None = None
    fecha_fin: date | None = None
    activo: bool | None = None


class PromocionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    descripcion: str | None = None
    tipo: str
    valor: float
    fecha_inicio: date
    fecha_fin: date
    activo: bool
    total_productos: int = 0
    productos: list[PromocionProductoOut] = []


class PromocionProductosUpdate(BaseModel):
    producto_ids: list[int] = []
