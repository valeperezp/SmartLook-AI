"""Schemas del módulo Vestidor virtual (CU05)."""
from pydantic import BaseModel


class VestidorPruebaOut(BaseModel):
    imagen_base64: str
    mime_type: str
