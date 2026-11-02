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

class ReporteGenerativoRequest(BaseModel):
    solicitud: str = Field(min_length=3, max_length=500)
    sucursal_id: int | None = None
    # None = se deduce de la solicitud ("última semana" → 7 días).
    dias: int | None = Field(default=None, ge=1, le=365)


class ReporteGenerativoOut(BaseModel):
    titulo: str
    contenido: str
    generado_con_ia: bool
    periodo_dias: int
    nombre_sucursal: str
    generado_en: datetime
    sugerencias: list[str]


class ExportarGenerativoRequest(BaseModel):
    """Exporta el reporte que el usuario ya tiene en pantalla (no se vuelve a llamar a la IA)."""
    formato: Literal["pdf", "excel"]
    titulo: str = Field(max_length=200)
    contenido: str = Field(max_length=20000)
    periodo_dias: int = Field(ge=1, le=365)
    sucursal_id: int | None = None
