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
    rol: str | None = None
    # CU1 5a: la suscripción venció y la sesión es de solo consulta.
    solo_lectura: bool = False
