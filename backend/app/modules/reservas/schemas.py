"""Esquemas Pydantic del módulo Reservas."""
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


# ---------- Items de reserva ----------
class ReservaItemCreate(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int = Field(default=1, ge=1)


class ReservaItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int
    nombre_producto: str = ""
    nombre_talla: str | None = None
    nombre_color: str | None = None
    precio_unitario: float = 0.0


# ---------- Reserva ----------
class ReservaCreate(BaseModel):
    sucursal_id: int
    horario_aproximado: datetime | None = None
    items: list[ReservaItemCreate] = Field(..., min_length=1)


class ReservaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    cliente_id: int
    sucursal_id: int
    estado: str
    horario_aproximado: datetime | None
    creada_en: datetime


class ReservaCompletaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    cliente_id: int
    sucursal_id: int
    estado: str
    horario_aproximado: datetime | None
    creada_en: datetime
    nombre_sucursal: str | None = None
    items: list[ReservaItemOut] = []
    total_items: int = 0
    total_unidades: int = 0
    total_estimado: float = 0.0
    nombre_cliente: str | None = None
    email_cliente: str | None = None

