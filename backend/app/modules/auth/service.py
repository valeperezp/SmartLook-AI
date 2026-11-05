"""Lógica de negocio del módulo Auth: registro, login y dependencias de autorización.

CU1 — Iniciar sesión en el contexto de una empresa: el token lleva el empresa_id
del usuario y cada request verifica que la empresa siga activa y con suscripción vigente.
"""
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy import func
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
# POST que no modifican datos (generar/exportar reportes, chat).
_RUTAS_PERMITIDAS_SOLO_LECTURA = ("/reportes/", "/ia/chat")

# Mensajes del documento (CU1 4b, CU6 3a, CU7 3a).
MSG_CREDENCIALES = "Credenciales inválidas"
MSG_USUARIO_INACTIVO = "Usuario inactivo, contacte al administrador de su empresa"
MSG_EMPRESA_SUSPENDIDA = "La empresa se encuentra suspendida"
MSG_SIN_SUSCRIPCION = "La empresa no tiene una suscripción asignada. Contacte al administrador de la plataforma."
MSG_VENCIDA_USUARIOS = "Suscripción vencida: no puede registrar usuarios"
MSG_VENCIDA_GENERAL = "Suscripción vencida: solo puede consultar información"


def validar_acceso_empresa(db: Session, usuario: Usuario, metodo: str = "GET", ruta: str = "") -> None:
    """Reglas de acceso por estado de la empresa y su suscripción (RN-06).

    - Empresa suspendida (o suscripción suspendida/cancelada): sus usuarios no inician sesión.
    - Suscripción vencida: inicia sesión, pero solo puede consultar.
    """
    if usuario.rol == ROL_SUPERADMIN:
        return
    empresa = usuario.empresa
    if empresa is None or not empresa.activa:
        raise HTTPException(status_code=403, detail=MSG_EMPRESA_SUSPENDIDA)
    suscripcion = empresas_service.suscripcion_actual(db, empresa.id)
    if suscripcion is None:
        raise HTTPException(status_code=403, detail=MSG_SIN_SUSCRIPCION)
    if suscripcion.estado != "activa":
        raise HTTPException(status_code=403, detail=MSG_EMPRESA_SUSPENDIDA)
    if (
        empresas_service.esta_vencida(suscripcion)
        and metodo not in _METODOS_DE_LECTURA
        and not ruta.startswith(_RUTAS_PERMITIDAS_SOLO_LECTURA)
    ):
        mensaje = MSG_VENCIDA_USUARIOS if ruta.startswith("/usuarios") else MSG_VENCIDA_GENERAL
        raise HTTPException(status_code=403, detail=mensaje)


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


def autenticar_usuario(db: Session, email: str, password: str, empresa_slug: str | None = None) -> Usuario:
    """CU1 pasos 3 a 5. Lanza el error del flujo alternativo que corresponda."""
    usuario = db.query(Usuario).filter(func.lower(Usuario.email) == email.lower()).first()
    # 3a: no se dice qué dato falló.
    if not usuario or not usuario.password_hash or not verify_password(password, usuario.password_hash):
        raise HTTPException(status_code=401, detail=MSG_CREDENCIALES)
    if empresa_slug and usuario.rol != ROL_SUPERADMIN:
        # Si el login indica empresa, el usuario tiene que pertenecer a ella.
        empresa = empresas_service.obtener_empresa_por_slug(db, empresa_slug)
        if empresa is None or usuario.empresa_id != empresa.id:
            raise HTTPException(status_code=401, detail=MSG_CREDENCIALES)
    if not usuario.activo:
        raise HTTPException(status_code=403, detail=MSG_USUARIO_INACTIVO)  # 3b
    validar_acceso_empresa(db, usuario)  # 4b y 5 (4a: el superadmin no tiene empresa)
    return usuario


def solo_lectura(db: Session, usuario: Usuario) -> bool:
    """CU1 5a: la suscripción venció; la sesión es de solo consulta."""
    if usuario.empresa_id is None:
        return False
    return empresas_service.esta_vencida(empresas_service.suscripcion_actual(db, usuario.empresa_id))


def emitir_token(usuario: Usuario, modo_solo_lectura: bool = False) -> str:
    """CU1 paso 6: el token lleva usuario, empresa (tenant), rol y sucursal asignada."""
    return create_access_token(
        {
            "sub": str(usuario.id),
            "empresa_id": usuario.empresa_id,
            "rol": usuario.rol,
            "sucursal_id": usuario.sucursal_id,
            "solo_lectura": modo_solo_lectura,
        }
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
