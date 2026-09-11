"""Esquemas Pydantic del módulo Usuarios."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

Rol = Literal["cliente", "administrador", "encargado_sucursal", "proveedor"]


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    email: str
    rol: str
    sucursal_id: int | None = None
    sucursal_nombre: str | None = None
    proveedor_id: int | None = None
    proveedor_nombre: str | None = None
    activo: bool
    creado_en: datetime


class UsuarioCreate(BaseModel):
    nombre: str
    email: str
    password: str
    rol: Rol = "cliente"
    sucursal_id: int | None = None
    proveedor_id: int | None = None


class UsuarioUpdate(BaseModel):
    nombre: str | None = None
    sucursal_id: int | None = None
    proveedor_id: int | None = None
    activo: bool | None = None


class UsuarioRolUpdate(BaseModel):
    rol: Rol
    sucursal_id: int | None = None
    proveedor_id: int | None = None
