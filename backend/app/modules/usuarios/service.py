"""Lógica de negocio del módulo Usuarios (CU6). Todo dentro de la empresa del administrador."""
from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.empresas import service as empresas_service
from app.modules.proveedores.models import Proveedor
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios import models, schemas
from app.shared.db.tenant import asegurar_de_empresa
from app.shared.security import hash_password


def listar_usuarios(db: Session, empresa_id: int) -> list[models.Usuario]:
    return (
        db.query(models.Usuario)
        .filter(models.Usuario.empresa_id == empresa_id)
        .order_by(models.Usuario.id)
        .all()
    )


def obtener_usuario(db: Session, usuario_id: int, empresa_id: int) -> models.Usuario | None:
    """Un usuario de otra empresa se trata como inexistente."""
    return (
        db.query(models.Usuario)
        .filter(models.Usuario.id == usuario_id, models.Usuario.empresa_id == empresa_id)
        .first()
    )


def obtener_usuario_por_email(db: Session, email: str) -> models.Usuario | None:
    # El email es único en toda la plataforma: identifica a la persona al iniciar sesión.
    return db.query(models.Usuario).filter(models.Usuario.email == email).first()


def _validar_referencias(db: Session, empresa_id: int, sucursal_id: int | None, proveedor_id: int | None) -> None:
    """La sucursal y el proveedor asignados tienen que ser de la misma empresa."""
    asegurar_de_empresa(db, Sucursal, sucursal_id, empresa_id, "Sucursal")
    asegurar_de_empresa(db, Proveedor, proveedor_id, empresa_id, "Proveedor")


def _cuenta_para_el_plan(rol: str, activo: bool) -> bool:
    """El límite de usuarios del plan cuenta solo personal activo, no clientes."""
    return activo and rol != "cliente"


def crear_usuario(db: Session, data: schemas.UsuarioCreate, empresa_id: int) -> models.Usuario:
    _validar_referencias(db, empresa_id, data.sucursal_id, data.proveedor_id)
    if _cuenta_para_el_plan(data.rol, True):
        empresas_service.verificar_limite(db, empresa_id, "usuarios")
    usuario = models.Usuario(
        nombre=data.nombre,
        email=data.email,
        password_hash=hash_password(data.password),
        rol=data.rol,
        empresa_id=empresa_id,
        sucursal_id=data.sucursal_id,
        proveedor_id=data.proveedor_id,
    )
    db.add(usuario)
    db.commit()
    db.refresh(usuario)
    return usuario


def _validar_no_es_ultimo_admin(db: Session, usuario: models.Usuario) -> None:
    """Impide dejar a la empresa sin administrador activo (al desactivarlo o cambiarle el rol)."""
    if usuario.rol != "administrador" or not usuario.activo:
        return
    # Se bloquean las filas de los admins activos: dos desactivaciones simultaneas no pueden dejar cero.
    # Cada empresa necesita su propio administrador.
    admins_activos = (
        db.query(models.Usuario.id)
        .filter(
            models.Usuario.rol == "administrador",
            models.Usuario.activo.is_(True),
            models.Usuario.empresa_id == usuario.empresa_id,
        )
        .order_by(models.Usuario.id)
        .with_for_update()
        .all()
    )
    if len(admins_activos) <= 1:
        raise HTTPException(
            status_code=400,
            detail="No se puede dejar a la empresa sin administrador. Asigna otro administrador primero.",
        )


def actualizar_usuario(
    db: Session, usuario_id: int, data: schemas.UsuarioUpdate, empresa_id: int
) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id, empresa_id)
    if not usuario:
        return None
    cambios = data.model_dump(exclude_unset=True)
    _validar_referencias(db, empresa_id, cambios.get("sucursal_id"), cambios.get("proveedor_id"))
    if cambios.get("activo") is False:
        _validar_no_es_ultimo_admin(db, usuario)
    if cambios.get("activo") is True and not _cuenta_para_el_plan(usuario.rol, usuario.activo) \
            and _cuenta_para_el_plan(usuario.rol, True):
        empresas_service.verificar_limite(db, usuario.empresa_id, "usuarios")
    for campo, valor in cambios.items():
        setattr(usuario, campo, valor)
    db.commit()
    db.refresh(usuario)
    return usuario


def actualizar_rol(
    db: Session, usuario_id: int, data: schemas.UsuarioRolUpdate, empresa_id: int
) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id, empresa_id)
    if not usuario:
        return None
    _validar_referencias(db, empresa_id, data.sucursal_id, data.proveedor_id)
    if usuario.rol == "administrador" and data.rol != "administrador":
        _validar_no_es_ultimo_admin(db, usuario)
    # Pasar un cliente a personal (cajero, encargado...) ocupa un lugar del plan.
    if not _cuenta_para_el_plan(usuario.rol, usuario.activo) and _cuenta_para_el_plan(data.rol, usuario.activo):
        empresas_service.verificar_limite(db, usuario.empresa_id, "usuarios")
    usuario.rol = data.rol
    if data.sucursal_id is not None:
        usuario.sucursal_id = data.sucursal_id
    if data.proveedor_id is not None:
        usuario.proveedor_id = data.proveedor_id
    db.commit()
    db.refresh(usuario)
    return usuario


def desactivar_usuario(db: Session, usuario_id: int, empresa_id: int) -> models.Usuario | None:
    usuario = obtener_usuario(db, usuario_id, empresa_id)
    if not usuario:
        return None
    _validar_no_es_ultimo_admin(db, usuario)
    usuario.activo = False
    db.commit()
    db.refresh(usuario)
    return usuario
