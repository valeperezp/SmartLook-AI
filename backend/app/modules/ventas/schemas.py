"""Esquemas Pydantic del módulo Ventas."""
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class VentaItemCreate(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int = Field(..., ge=1)


class VentaItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int
    precio_unitario: float
    nombre_producto: str = ""
    nombre_talla: str | None = None
    nombre_color: str | None = None
    subtotal: float = 0.0


class VentaPresencialCreate(BaseModel):
    sucursal_id: int
    cliente_id: int | None = None
    items: list[VentaItemCreate] = Field(..., min_length=1)


class VentaOnlineCreate(BaseModel):
    sucursal_id: int
    items: list[VentaItemCreate] = Field(..., min_length=1)


class VentaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    cliente_id: int | None = None
    sucursal_id: int
    cajero_id: int | None = None
    canal: str
    estado: str
    total: float
    creada_en: datetime
    nombre_sucursal: str | None = None
    nombre_cajero: str | None = None
    nombre_cliente: str | None = None
    items: list[VentaItemOut] = []
    total_items: int = 0
    total_unidades: int = 0
