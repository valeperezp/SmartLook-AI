"""Lógica de negocio del módulo Auth: registro, login y dependencias de autorización.

CU1 — Iniciar sesión en el contexto de una empresa: el token lleva el empresa_id
del usuario y cada request verifica que la empresa siga activa y con suscripción vigente.
"""
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
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


_METODOS_DE_LECTURA = {"GET", "HEAD", "OPTIONS"}
# POST que no modifican datos (generar/exportar reportes, chat) o que sirven para regularizar la suscripción.
_RUTAS_PERMITIDAS_SOLO_LECTURA = ("/mi-empresa/suscripcion", "/reportes/", "/ia/chat")


def validar_acceso_empresa(db: Session, usuario: Usuario, metodo: str = "GET", ruta: str = "") -> None:
    """Reglas de acceso por estado de la empresa y su suscripción.

    - Empresa dada de baja, suscripción suspendida o cancelada: no puede iniciar sesión (RN-06).
    - Suscripción vencida: inicia sesión, pero solo puede consultar (RN-06).
    """
    if usuario.rol == ROL_SUPERADMIN:
        return
    empresa = usuario.empresa
    if empresa is None or not empresa.activa:
        raise HTTPException(status_code=403, detail="La empresa no está habilitada en la plataforma")
    suscripcion = empresas_service.suscripcion_actual(db, empresa.id)
    if suscripcion is None or suscripcion.estado != "activa":
        raise HTTPException(
            status_code=403,
            detail="La suscripción de la empresa está suspendida. Contactá al administrador de la plataforma.",
        )
    if (
        empresas_service.esta_vencida(suscripcion)
        and metodo not in _METODOS_DE_LECTURA
        and not ruta.startswith(_RUTAS_PERMITIDAS_SOLO_LECTURA)
    ):
        raise HTTPException(
            status_code=403,
            detail="La suscripción de la empresa venció: solo podés consultar información hasta renovarla.",
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


def get_current_user(
    request: Request, token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)
) -> Usuario:
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
    validar_acceso_empresa(db, usuario, request.method, request.url.path)
    return usuario


def empresa_actual_id(usuario: Usuario = Depends(get_current_user)) -> int:
    """Dependencia: id de la empresa del usuario logueado (tenant de la request)."""
    if usuario.empresa_id is None:
        raise HTTPException(status_code=403, detail="Esta acción requiere pertenecer a una empresa")
    return usuario.empresa_id


_oauth2_opcional = OAuth2PasswordBearer(tokenUrl="/auth/login", auto_error=False)


def empresa_contexto(
    request: Request,
    token: str | None = Depends(_oauth2_opcional),
    db: Session = Depends(get_db),
) -> int:
    """Dependencia para endpoints públicos (catálogo, sucursales): ¿de qué tienda son los datos?

    1. Con sesión: la empresa del usuario.
    2. Sin sesión: el header X-Empresa (slug).
    3. Si no viene nada: la tienda por defecto (la app móvil de clientes).
    """
    if token:
        usuario = get_current_user(request, token, db)
        if usuario.empresa_id is not None:
            return usuario.empresa_id
    slug = request.headers.get("X-Empresa") or settings.empresa_por_defecto
    empresa = _empresa_por_slug_o_404(db, slug)
    if not empresa.activa:
        raise HTTPException(status_code=404, detail="No existe una empresa con ese identificador")
    return empresa.id


def require_roles(*roles: str):
    def checker(usuario: Usuario = Depends(get_current_user)) -> Usuario:
        if usuario.rol not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No tiene permisos para esta acción")
        return usuario

    return checker
