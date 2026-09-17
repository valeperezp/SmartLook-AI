"""Esquemas Pydantic del módulo reportes (CU13 — Consultar reportes y dashboards)."""
from pydantic import BaseModel


class ReservasPorEstado(BaseModel):
    estado: str
    cantidad: int


class ReservasPorSucursal(BaseModel):
    sucursal_id: int
    nombre_sucursal: str
    cantidad_reservas: int
    total_unidades: int


class ProductoMasReservado(BaseModel):
    producto_id: int
    nombre_producto: str
    nombre_categoria: str | None = None
    total_unidades: int
    total_reservas: int


class ReservasPorDia(BaseModel):
    fecha: str
    cantidad: int


class ResumenReportes(BaseModel):
    total_reservas: int
    total_unidades_reservadas: int
    reservas_por_estado: list[ReservasPorEstado]
    inventario_disponible: int
    inventario_reservado: int
    productos_stock_bajo: int
    productos_agotados: int
