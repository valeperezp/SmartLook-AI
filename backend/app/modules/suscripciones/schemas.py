"""Esquemas Pydantic del módulo Suscripciones de stock."""
from pydantic import BaseModel, Field


class SuscripcionCreate(BaseModel):
    producto_id: int
    talla_id: int | None = None  # None = cualquier talla
    color_id: int | None = None  # None = cualquier color
    sucursal_id: int | None = None  # None = en cualquier sucursal
    uuid: str | None = Field(default=None, min_length=1, max_length=64)  # id local de la app: reenviar no duplica


class SuscripcionOut(BaseModel):
    id: int
    uuid: str | None = None
    producto_id: int
    nombre_producto: str
    talla_id: int | None = None
    nombre_talla: str | None = None
    color_id: int | None = None
    nombre_color: str | None = None
    sucursal_id: int | None = None
    nombre_sucursal: str | None = None
    descripcion: str  # "Camiseta · Talla M · Blanco"
    estado: str  # pendiente | notificado
    fecha: str | None = None
    notificado_en: str | None = None
    visto: bool = False


class MarcarVistasOut(BaseModel):
    marcadas: int
