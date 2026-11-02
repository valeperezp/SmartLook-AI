"""Esquemas Pydantic de transferencias entre sucursales (CU19)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

EstadoTransferencia = Literal["solicitada", "aprobada", "en_transito", "recibida", "rechazada", "cancelada"]
Accion = Literal["aprobar", "rechazar", "despachar", "recibir", "cancelar"]


class TransferenciaItemCreate(BaseModel):
    inventario_id: int = Field(description="Registro de inventario de la sucursal de origen")
    cantidad: int = Field(gt=0)


class TransferenciaCreate(BaseModel):
    sucursal_origen_id: int
    sucursal_destino_id: int
    motivo: str | None = Field(default=None, max_length=255)
    items: list[TransferenciaItemCreate] = Field(min_length=1)


class AccionRequest(BaseModel):
    comentario: str | None = Field(default=None, max_length=255)


class TransferenciaItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    inventario_origen_id: int
    producto_id: int
    nombre_producto: str
    nombre_talla: str | None = None
    nombre_color: str | None = None
    cantidad: int


class HistorialOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    estado_anterior: str | None = None
    estado_nuevo: str
    nombre_usuario: str
    comentario: str | None = None
    creado_en: datetime


class TransferenciaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    sucursal_origen_id: int
    sucursal_destino_id: int
    nombre_origen: str
    nombre_destino: str
    estado: EstadoTransferencia
    motivo: str | None = None
    nombre_solicitante: str
    total_unidades: int
    creado_en: datetime
    actualizado_en: datetime | None = None
    items: list[TransferenciaItemOut]
    historial: list[HistorialOut]
    # Acciones que el usuario que consulta puede ejecutar ahora mismo.
    acciones: list[Accion] = []
