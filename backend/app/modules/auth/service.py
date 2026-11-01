"""Lógica de negocio del módulo Auth: registro, login y dependencias de autorización.

CU1 — Iniciar sesión en el contexto de una empresa: el token lleva el empresa_id
del usuario y cada request verifica que la empresa siga activa y con suscripción vigente.
"""
from fastapi import Depends, HTTPException, status
from jose import JWTError
from sqlalchemy.orm import Session

from app.modules.auth import schemas
from app.modules.empresas import service as empresas_service
from app.modules.empresas.models import Empresa
from app.modules.usuarios.models import Usuario
from app.shared.core.config import settings
from app.shared.db.session import get_db
from app.shared.security import (
    create_access_token,
    decode_access_token,
    hash_password,
    oauth2_scheme,
    verify_password,
)

ROL_SUPERADMIN = "superadmin"


def _empresa_por_slug_o_404(db: Session, slug: str) -> Empresa:
    empresa = empresas_service.obtener_empresa_por_slug(db, slug)
    if not empresa:
        raise HTTPException(status_code=404, detail="No existe una empresa con ese identificador")
    return empresa


def validar_acceso_empresa(db: Session, usuario: Usuario) -> None:
    """403 si la empresa del usuario está dada de baja o sin suscripción vigente."""
    if usuario.rol == ROL_SUPERADMIN:
        return
    empresa = usuario.empresa
    if empresa is None or not empresa.activa:
        raise HTTPException(status_code=403, detail="La empresa no está habilitada en la plataforma")
    if empresas_service.suscripcion_vigente(db, empresa.id) is None:
        raise HTTPException(
            status_code=403,
            detail="La suscripción de la empresa no está vigente. Contactá al administrador.",
        )


def registrar_usuario(db: Session, data: schemas.RegistroRequest) -> Usuario:
    if db.query(Usuario).filter(Usuario.email == data.email).first():
        raise HTTPException(status_code=400, detail="Ese email ya está registrado")

    # Los clientes se registran en la tienda de una empresa; la app móvil no manda
    # empresa, así que cae en la tienda por defecto.
    empresa = _empresa_por_slug_o_404(db, data.empresa or settings.empresa_por_defecto)
    if not empresa.activa:
        raise HTTPException(status_code=403, detail="La empresa no está habilitada en la plataforma")

    usuario = Usuario(
        nombre=data.nombre,
        email=data.email,
        password_hash=hash_password(data.password),
        rol="cliente",
        empresa_id=empresa.id,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


def autenticar_usuario(db: Session, email: str, password: str, empresa_slug: str | None = None) -> Usuario | None:
    usuario = db.query(Usuario).filter(Usuario.email == email).first()
    if not usuario or not usuario.password_hash or not verify_password(password, usuario.password_hash):
        return None
    if not usuario.activo:
        return None
    if empresa_slug and usuario.rol != ROL_SUPERADMIN:
        # Si el login indica empresa, el usuario tiene que pertenecer a ella.
        empresa = _empresa_por_slug_o_404(db, empresa_slug)
        if usuario.empresa_id != empresa.id:
            return None
    validar_acceso_empresa(db, usuario)
    return usuario


def emitir_token(usuario: Usuario) -> str:
    return create_access_token(
        {"sub": str(usuario.id), "empresa_id": usuario.empresa_id, "rol": usuario.rol}
    )


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
        usuario_id = int(usuario_id)
    except (JWTError, ValueError, TypeError):
        raise credentials_exception

    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if usuario is None or not usuario.activo:
        raise credentials_exception
    # Un token emitido para otra empresa (o antes de un cambio de empresa) ya no sirve.
    if payload.get("empresa_id") != usuario.empresa_id:
        raise credentials_exception
    validar_acceso_empresa(db, usuario)
    return usuario


def empresa_actual_id(usuario: Usuario = Depends(get_current_user)) -> int:
    """Dependencia: id de la empresa del usuario logueado (tenant de la request)."""
    if usuario.empresa_id is None:
        raise HTTPException(status_code=403, detail="Esta acción requiere pertenecer a una empresa")
    return usuario.empresa_id


def require_roles(*roles: str):
    def checker(usuario: Usuario = Depends(get_current_user)) -> Usuario:
        if usuario.rol not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No tiene permisos para esta acción")
        return usuario

    return checker
