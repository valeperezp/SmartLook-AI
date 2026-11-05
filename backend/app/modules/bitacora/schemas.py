from datetime import datetime

from pydantic import BaseModel, ConfigDict


class BitacoraOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    empresa_id: int | None = None
    nombre_empresa: str | None = None
    usuario_id: int | None = None
    nombre_usuario: str | None = None
    email_usuario: str | None = None
    accion: str
    detalle: str | None = None
    ip: str | None = None
    creado_en: datetime
