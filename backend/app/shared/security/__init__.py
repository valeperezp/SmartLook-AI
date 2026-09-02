"""Utilidades puras de seguridad: hashing de passwords y JWT.

No depende de ningún módulo de negocio (ni siquiera de Usuario) — cada
módulo que necesite autenticación importa desde acá.
"""
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

from app.shared.core.config import settings

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))


def create_access_token(data: dict, expires_delta: timedelta | None = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.access_token_expire_minutes)
    )
    to_encode["exp"] = expire
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


def decode_access_token(token: str) -> dict:
    """Lanza jose.JWTError si el token es inválido o expiró."""
    return jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
