"""Schemas del módulo Vestidor virtual (CU05)."""
from pydantic import BaseModel


class VestidorPruebaOut(BaseModel):
    imagen_resultado_url: str
    producto_id: int
    producto_nombre: str
    desde_cache: bool = False
