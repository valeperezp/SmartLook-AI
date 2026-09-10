"""Esquemas Pydantic del módulo Inventario."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


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


class InventarioCreate(BaseModel):
    producto_id: int
    sucursal_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad_inicial: int = Field(default=0, ge=0, description="Cantidad disponible inicial")
    stock_minimo: int = Field(default=5, ge=0, description="Nivel mínimo de alerta")


class MovimientoCreate(BaseModel):
    inventario_id: int
    tipo: Literal["entrada", "salida"]
    cantidad: int = Field(gt=0, description="Cantidad mayor a cero para entrada o salida")
    motivo: str | None = Field(default=None, description="Motivo del movimiento o referencia de remisión")


class AjusteStockCreate(BaseModel):
    inventario_id: int
    nueva_cantidad: int = Field(ge=0, description="Nueva cantidad física disponible tras conteo")
    motivo: str | None = Field(default="Ajuste por conteo físico / auditoría", description="Motivo del ajuste")


class StockMinimoUpdate(BaseModel):
    stock_minimo: int = Field(ge=0, description="Nuevo nivel de stock mínimo")


class MovimientoInventarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    inventario_id: int
    tipo: str
    cantidad: int
    motivo: str | None = None
    usuario_id: int | None = None
    nombre_usuario: str | None = None
    nombre_producto: str | None = None
    nombre_sucursal: str | None = None
    creado_en: datetime


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
