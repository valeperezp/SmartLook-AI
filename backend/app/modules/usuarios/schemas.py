"""Esquemas Pydantic del módulo Usuarios."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict

Rol = Literal["cliente", "administrador"]


class UsuarioOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    email: str
    rol: str
    activo: bool
    creado_en: datetime


class UsuarioCreate(BaseModel):
    nombre: str
    email: str
    password: str
    rol: Rol = "cliente"


class UsuarioUpdate(BaseModel):
    nombre: str | None = None
    activo: bool | None = None


class UsuarioRolUpdate(BaseModel):
    rol: Rol
