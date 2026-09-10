"""Esquemas Pydantic del módulo Inventario."""
from pydantic import BaseModel, ConfigDict


class InventarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    producto_id: int
    sucursal_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad_disponible: int
    cantidad_reservada: int
    cantidad_vendida: int
    stock_minimo: int
    nombre_producto: str
    nombre_sucursal: str
    nombre_talla: str | None = None
    nombre_color: str | None = None
    estado: str  # disponible, bajo, agotado


class ResumenInventario(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    total_disponibles: int
    total_reservados: int
    total_vendidos: int
    productos_agotados: int
    productos_stock_bajo: int
    total_sucursales: int


class AlertaStock(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    inventario_id: int
    nombre_producto: str
    nombre_sucursal: str
    cantidad_disponible: int
    stock_minimo: int
    mensaje: str
