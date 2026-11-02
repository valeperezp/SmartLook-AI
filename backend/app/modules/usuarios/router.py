"""Endpoints HTTP del módulo Usuarios (CU6). Solo administrador, dentro de su empresa."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/usuarios", tags=["usuarios"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.UsuarioOut])
def listar_usuarios(db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.listar_usuarios(db, admin.empresa_id)


@router.get("/{usuario_id}", response_model=schemas.UsuarioOut)
def obtener_usuario(usuario_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    usuario = service.obtener_usuario(db, usuario_id, admin.empresa_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.post("", response_model=schemas.UsuarioOut, status_code=201)
def crear_usuario(data: schemas.UsuarioCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    if service.obtener_usuario_por_email(db, data.email):
        raise HTTPException(status_code=400, detail="Ese email ya está registrado")
    return service.crear_usuario(db, data, admin.empresa_id)


@router.patch("/{usuario_id}", response_model=schemas.UsuarioOut)
def actualizar_usuario(
    usuario_id: int, data: schemas.UsuarioUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    usuario = service.actualizar_usuario(db, usuario_id, data, admin.empresa_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.patch("/{usuario_id}/rol", response_model=schemas.UsuarioOut)
def actualizar_rol(
    usuario_id: int, data: schemas.UsuarioRolUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    usuario = service.actualizar_rol(db, usuario_id, data, admin.empresa_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.delete("/{usuario_id}", response_model=schemas.UsuarioOut)
def desactivar_usuario(usuario_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    usuario = service.desactivar_usuario(db, usuario_id, admin.empresa_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario
