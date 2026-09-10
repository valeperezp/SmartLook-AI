"""Lógica de negocio del módulo Usuarios."""
from sqlalchemy.orm import Session

from app.modules.usuarios import models, schemas
from app.shared.security import hash_password


def listar_usuarios(db: Session) -> list[models.Usuario]:
    return db.query(models.Usuario).order_by(models.Usuario.id).all()


def obtener_usuario(db: Session, usuario_id: int) -> models.Usuario | None:
    return db.query(models.Usuario).filter(models.Usuario.id == usuario_id).first()


def obtener_usuario_por_email(db: Session, email: str) -> models.Usuario | None:
    return db.query(models.Usuario).filter(models.Usuario.email == email).first()


def crear_usuario(db: Session, data: schemas.UsuarioCreate) -> models.Usuario:
    usuario = models.Usuario(
        nombre=data.nombre,
        email=data.email,
        password_hash=hash_password(data.password),
        rol=data.rol,
        sucursal_id=data.sucursal_id,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


def actualizar_usuario(db: Session, usuario_id: int, data: schemas.UsuarioUpdate) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id)
    if not usuario:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(usuario, campo, valor)
    db.commit()
    db.refresh(usuario)
    return usuario


def actualizar_rol(db: Session, usuario_id: int, data: schemas.UsuarioRolUpdate) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id)
    if not usuario:
        return None
    usuario.rol = data.rol
    if data.sucursal_id is not None:
        usuario.sucursal_id = data.sucursal_id
    db.commit()
    db.refresh(usuario)
    return usuario


def desactivar_usuario(db: Session, usuario_id: int) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id)
    if not usuario:
        return None
    usuario.activo = False
    db.commit()
    db.refresh(usuario)
    return usuario
