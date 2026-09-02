"""Esquemas Pydantic del módulo Auth."""
from pydantic import BaseModel


class RegistroRequest(BaseModel):
    nombre: str
    email: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
