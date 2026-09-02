"""Endpoints HTTP del módulo Usuarios. Todo protegido: solo administrador."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/usuarios", tags=["usuarios"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.UsuarioOut], dependencies=[Depends(admin_only)])
def listar_usuarios(db: Session = Depends(get_db)):
    return service.listar_usuarios(db)


@router.get("/{usuario_id}", response_model=schemas.UsuarioOut, dependencies=[Depends(admin_only)])
def obtener_usuario(usuario_id: int, db: Session = Depends(get_db)):
    usuario = service.obtener_usuario(db, usuario_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.post("", response_model=schemas.UsuarioOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_usuario(data: schemas.UsuarioCreate, db: Session = Depends(get_db)):
    if service.obtener_usuario_por_email(db, data.email):
        raise HTTPException(status_code=400, detail="Ese email ya está registrado")
    return service.crear_usuario(db, data)


@router.patch("/{usuario_id}", response_model=schemas.UsuarioOut, dependencies=[Depends(admin_only)])
def actualizar_usuario(usuario_id: int, data: schemas.UsuarioUpdate, db: Session = Depends(get_db)):
    usuario = service.actualizar_usuario(db, usuario_id, data)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.patch("/{usuario_id}/rol", response_model=schemas.UsuarioOut, dependencies=[Depends(admin_only)])
def actualizar_rol(usuario_id: int, data: schemas.UsuarioRolUpdate, db: Session = Depends(get_db)):
    usuario = service.actualizar_rol(db, usuario_id, data)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario


@router.delete("/{usuario_id}", response_model=schemas.UsuarioOut, dependencies=[Depends(admin_only)])
def desactivar_usuario(usuario_id: int, db: Session = Depends(get_db)):
    usuario = service.desactivar_usuario(db, usuario_id)
    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")
    return usuario
