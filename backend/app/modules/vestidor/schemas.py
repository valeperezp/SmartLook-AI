"""Schemas del módulo Vestidor virtual (CU05)."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class VestidorPruebaOut(BaseModel):
    imagen_resultado_url: str
    producto_id: int
    producto_nombre: str
    desde_cache: bool = False


class VestidorJobCrearResponse(BaseModel):
    job_id: int
    estado: str
    mensaje: str


class VestidorJobEstado(BaseModel):
    job_id: int
    estado: str
    imagen_resultado_url: Optional[str] = None
    error: Optional[str] = None
    producto_id: int
    creado_en: datetime
    actualizado_en: datetime

    class Config:
        from_attributes = True
