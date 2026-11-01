"""Esquemas Pydantic del módulo Auth."""
from pydantic import BaseModel


class RegistroRequest(BaseModel):
    nombre: str
    email: str
    password: str
    empresa: str | None = None  # slug de la tienda; None = empresa por defecto


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
