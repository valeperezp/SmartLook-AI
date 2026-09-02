"""Esquemas Pydantic del módulo Sucursales."""
from pydantic import BaseModel, ConfigDict


class SucursalBase(BaseModel):
    nombre: str
    direccion: str
    ciudad: str | None = None
    telefono: str | None = None


class SucursalCreate(SucursalBase):
    pass


class SucursalUpdate(BaseModel):
    nombre: str | None = None
    direccion: str | None = None
    ciudad: str | None = None
    telefono: str | None = None
    activa: bool | None = None


class SucursalOut(SucursalBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    activa: bool
