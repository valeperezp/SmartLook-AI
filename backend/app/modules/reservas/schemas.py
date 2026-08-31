"""Esquemas Pydantic del módulo Reservas."""
from datetime import datetime
from pydantic import BaseModel, ConfigDict


class ReservaCreate(BaseModel):
    cliente_id: int
    sucursal_id: int
    horario_aproximado: datetime | None = None
    producto_ids: list[int] = []  # prendas seleccionadas para la reserva


class ReservaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    cliente_id: int
    sucursal_id: int
    estado: str
    horario_aproximado: datetime | None
