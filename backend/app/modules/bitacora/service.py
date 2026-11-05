"""Registro y consulta de la bitácora.

- `registrar` agrega la entrada a la sesión del caso de uso: se guarda junto con la operación
  (si la operación falla y se hace rollback, la entrada tampoco queda).
- `registrar_aparte` la guarda en su propia transacción: sirve para dejar constancia de un intento
  rechazado aunque la operación principal termine en error (CU6 6b).
"""
from fastapi import Request
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from app.modules.bitacora.models import Bitacora
from app.shared.db.session import SessionLocal

# Acciones de la plataforma: son las que ve el superadmin (RN-03: no ve la operación comercial).
PREFIJOS_PLATAFORMA = ("empresa.", "plan.", "suscripcion.")


def _ip(request: Request | None) -> str | None:
    if request is None:
        return None
    reenviada = request.headers.get("x-forwarded-for")
    if reenviada:
        return reenviada.split(",")[0].strip()[:60]
    return request.client.host[:60] if request.client else None


def _entrada(accion: str, detalle: str | None, usuario=None, empresa_id: int | None = None,
             request: Request | None = None) -> Bitacora:
    if empresa_id is None and usuario is not None:
        empresa_id = usuario.empresa_id
    return Bitacora(
        accion=accion,
        detalle=(detalle or "")[:500] or None,
        usuario_id=usuario.id if usuario is not None else None,
        empresa_id=empresa_id,
        ip=_ip(request),
    )


def registrar(db: Session, accion: str, detalle: str | None = None, *, usuario=None,
              empresa_id: int | None = None, request: Request | None = None) -> None:
    db.add(_entrada(accion, detalle, usuario, empresa_id, request))


def registrar_aparte(accion: str, detalle: str | None = None, *, usuario=None,
                     empresa_id: int | None = None, request: Request | None = None) -> None:
    db = SessionLocal()
    try:
        db.add(_entrada(accion, detalle, usuario, empresa_id, request))
        db.commit()
    finally:
        db.close()


def listar(db: Session, usuario, accion: str | None = None, limite: int = 200) -> list[Bitacora]:
    query = db.query(Bitacora).options(joinedload(Bitacora.usuario), joinedload(Bitacora.empresa))
    if usuario.empresa_id is None:
        # Superadmin: acciones sobre empresas, planes y suscripciones, y sus propios accesos.
        query = query.filter(
            or_(Bitacora.usuario_id == usuario.id, *[Bitacora.accion.startswith(p) for p in PREFIJOS_PLATAFORMA])
        )
    else:
        query = query.filter(Bitacora.empresa_id == usuario.empresa_id)
    if accion:
        query = query.filter(Bitacora.accion.startswith(accion))
    return query.order_by(Bitacora.id.desc()).limit(min(max(limite, 1), 500)).all()
