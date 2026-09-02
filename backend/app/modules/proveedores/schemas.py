"""Esquemas Pydantic del módulo Proveedores."""
from pydantic import BaseModel, ConfigDict


class ProveedorBase(BaseModel):
    nombre: str
    contacto: str | None = None
    telefono: str | None = None
    email: str | None = None


class ProveedorCreate(ProveedorBase):
    pass


class ProveedorUpdate(BaseModel):
    nombre: str | None = None
    contacto: str | None = None
    telefono: str | None = None
    email: str | None = None
    activo: bool | None = None


class ProveedorOut(ProveedorBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    activo: bool
