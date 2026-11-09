"""Esquemas Pydantic del módulo reportes (CU14 reporte generativo, CU15 dashboard)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


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


# ---------- Dashboard (CU15) ----------

class ResumenVentas(BaseModel):
    cantidad_ventas: int
    ingresos: float
    ticket_promedio: float
    unidades_vendidas: int
    variacion_ingresos_pct: float | None = None


class VentasPorDia(BaseModel):
    fecha: str
    cantidad: int
    ingresos: float


class VentasPorSucursal(BaseModel):
    sucursal_id: int
    nombre_sucursal: str
    cantidad_ventas: int
    ingresos: float


class VentasPorCategoria(BaseModel):
    categoria: str
    unidades: int
    ingresos: float


class VentasPorCanal(BaseModel):
    canal: str
    cantidad: int
    ingresos: float


class ProductoMasVendido(BaseModel):
    producto_id: int
    nombre_producto: str
    nombre_categoria: str | None = None
    unidades: int
    ingresos: float


class AlertaStock(BaseModel):
    inventario_id: int
    nombre_producto: str
    nombre_sucursal: str
    cantidad_disponible: int
    stock_minimo: int
    mensaje: str


class Dashboard(BaseModel):
    periodo_dias: int
    nombre_sucursal: str
    ventas: ResumenVentas
    ventas_por_dia: list[VentasPorDia]
    ventas_por_sucursal: list[VentasPorSucursal]
    ventas_por_categoria: list[VentasPorCategoria]
    ventas_por_canal: list[VentasPorCanal]
    top_vendidos: list[ProductoMasVendido]
    resumen: ResumenReportes
    reservas_por_dia: list[ReservasPorDia]
    top_reservados: list[ProductoMasReservado]
    alertas_stock: list[AlertaStock]


# ---------- Reporte generativo (CU14) ----------

class SolicitudReporte(BaseModel):
    solicitud: str = Field(min_length=3, max_length=500)
    # Intención del reporte que el usuario está viendo: la frase puede continuar la conversación.
    contexto: dict | None = None


class IntencionReporte(BaseModel):
    """Intención validable: la arma la IA (paso 5) o el formulario de reportes convencionales."""
    tipo: str
    fecha_inicio: str | None = None
    fecha_fin: str | None = None
    sucursal_ids: list[int] | None = None
    categoria_ids: list[int] | None = None
    producto_ids: list[int] | None = None
    limite: int | None = Field(default=None, ge=1, le=50)
    grafico: Literal["barras", "lineas", "torta"] | None = None


class ExportarReporteRequest(BaseModel):
    formato: Literal["pdf", "excel"]
    intencion: IntencionReporte
    solicitud: str | None = Field(default=None, max_length=500)