"""Esquemas Pydantic del módulo Devoluciones."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ItemDevolucionIn(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int = Field(..., ge=1)


class DevolucionCreate(BaseModel):
    """Registra un cambio o una devolución de una venta ya hecha (desde la web)."""

    venta_id: int
    tipo: Literal["devolucion", "cambio"] = "devolucion"  # devolucion = solo reembolso · cambio = se lleva otra prenda
    motivo: str | None = Field(default=None, max_length=255)
    items_devueltos: list[ItemDevolucionIn] = Field(..., min_length=1)
    items_nuevos: list[ItemDevolucionIn] = []  # solo en un cambio: lo que se lleva en su lugar
    uuid: str | None = Field(default=None, min_length=1, max_length=64)  # opcional: reintentar no duplica


class ItemDevolucionOut(BaseModel):
    tipo_item: str  # devuelto | nuevo
    producto_id: int
    nombre_producto: str
    talla_id: int | None = None
    nombre_talla: str | None = None
    color_id: int | None = None
    nombre_color: str | None = None
    cantidad: int
    precio_unitario: float


class DevolucionOut(BaseModel):
    id: int
    uuid: str
    venta_id: int
    tipo: str
    motivo: str | None = None
    total_devuelto: float  # lo que se reembolsa (al precio de la venta original)
    total_nuevo: float  # lo que cuesta lo que se lleva (al precio vigente)
    diferencia: float  # total_nuevo - total_devuelto: >0 el cliente paga la diferencia · <0 se le devuelve
    items: list[ItemDevolucionOut] = []


class ItemVentaDevolvible(BaseModel):
    producto_id: int
    nombre_producto: str
    talla_id: int | None = None
    nombre_talla: str | None = None
    color_id: int | None = None
    nombre_color: str | None = None
    cantidad_vendida: int
    cantidad_devuelta: int
    cantidad_devolvible: int
    precio_unitario: float


class VentaDevolvibleOut(BaseModel):
    venta_id: int
    uuid: str | None = None  # id con el que la app móvil mandó la venta (si vino de una app)
    recibo: str  # lo que ve el cliente en su ticket: el uuid abreviado o #id
    sucursal_id: int
    nombre_sucursal: str | None = None
    estado: str
    total: float
    creada_en: str
    plazo_dias: int
    dias_transcurridos: int
    dentro_de_plazo: bool  # informativo: la decisión la toma el servidor al registrar
    items: list[ItemVentaDevolvible] = []


class ConfiguracionOut(BaseModel):
    plazo_dias: int


class ConfiguracionIn(BaseModel):
    plazo_dias: int = Field(..., ge=1, le=3650)


# ---------------------------------------------------------------------------------------------------------------
# Reembolsos: devolución de DINERO de un pedido (reserva o venta) cancelado
# ---------------------------------------------------------------------------------------------------------------
class ReembolsoSolicitud(BaseModel):
    """Qué pedido cancelado se reembolsa: una reserva O una venta (exactamente una)."""

    reserva_id: int | None = None
    venta_id: int | None = None

    @model_validator(mode="after")
    def _un_solo_origen(self):
        if (self.reserva_id is None) == (self.venta_id is None):
            raise ValueError("Indica la reserva o la venta (solo una de las dos)")
        return self


class ReembolsoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    estado: str  # pendiente | reembolsado
    reserva_id: int | None = None
    venta_id: int | None = None
    cliente_id: int | None = None
    monto: float = 0.0
    tiene_qr: bool = False
    qr_devolucion_url: str | None = None  # la imagen del QR bancario que subió el cliente
    qr_subido_en: datetime | None = None
    procesado_en: datetime | None = None


class ReembolsoDetalleOut(ReembolsoOut):
    """Lo que ve el personal: además, de quién y de qué sucursal es."""

    origen: str  # reserva | venta
    sucursal_id: int
    nombre_sucursal: str | None = None
    nombre_cliente: str | None = None
    email_cliente: str | None = None
