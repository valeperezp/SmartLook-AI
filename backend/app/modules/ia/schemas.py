"""Esquemas Pydantic del módulo ia (CU06/CU20 — recomendaciones y análisis de preferencias)."""
from pydantic import BaseModel


class PreferenciaDetectada(BaseModel):
    tipo: str  # categoria, temporada, coleccion
    nombre: str
    peso: int  # cantidad de unidades reservadas asociadas a esta preferencia


class PerfilPreferencias(BaseModel):
    tiene_historial: bool
    total_reservas_analizadas: int
    preferencias: list[PreferenciaDetectada]


class ProductoRecomendado(BaseModel):
    producto_id: int
    nombre_producto: str
    precio: float
    nombre_categoria: str | None = None
    modelo_ar_url: str | None = None
    motivo: str
    puntaje: int
