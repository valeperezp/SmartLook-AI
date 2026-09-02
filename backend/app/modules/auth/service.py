"""Lógica de negocio del módulo Auth: registro, login y dependencias de autorización."""
from fastapi import Depends, HTTPException, status
from jose import JWTError
from sqlalchemy.orm import Session

from app.modules.auth import schemas
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db
from app.shared.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    oauth2_scheme,
    verify_password,
)


def registrar_usuario(db: Session, data: schemas.RegistroRequest) -> Usuario:
    if db.query(Usuario).filter(Usuario.email == data.email).first():
        raise HTTPException(status_code=400, detail="Ese email ya está registrado")

    usuario = Usuario(
        nombre=data.nombre,
        email=data.email,
        password_hash=hash_password(data.password),
        rol="cliente",
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


def autenticar_usuario(db: Session, email: str, password: str) -> Usuario | None:
    usuario = db.query(Usuario).filter(Usuario.email == email).first()
    if not usuario or not usuario.password_hash or not verify_password(password, usuario.password_hash):
        return None
    return usuario


def emitir_token(usuario: Usuario) -> str:
    return create_access_token({"sub": str(usuario.id)})


def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> Usuario:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="No se pudo validar la sesión",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_access_token(token)
        usuario_id = payload.get("sub")
        if usuario_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    usuario = db.query(Usuario).filter(Usuario.id == int(usuario_id)).first()
    if usuario is None or not usuario.activo:
        raise credentials_exception
    return usuario


def require_roles(*roles: str):
    def checker(usuario: Usuario = Depends(get_current_user)) -> Usuario:
        if usuario.rol not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No tiene permisos para esta acción")
        return usuario

    return checker
