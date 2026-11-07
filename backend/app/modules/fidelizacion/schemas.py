"""Esquemas Pydantic del módulo Fidelización."""
from pydantic import BaseModel, Field


class MisPuntos(BaseModel):
    cliente_id: int
    saldo: int  # puntos disponibles
    valor_punto_centavos: int  # regla de la empresa: centavos de descuento por punto (y de gasto por punto ganado)
    valor_saldo_centavos: int  # lo que valen hoy todos sus puntos como descuento


class ReglaPuntosIn(BaseModel):
    valor_punto_centavos: int = Field(..., ge=1, le=10_000_000)


class ReglaPuntosOut(BaseModel):
    valor_punto_centavos: int
