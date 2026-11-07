"""Endpoint de sincronización de la app móvil offline."""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.modules.auth.service import get_current_user, require_roles
from app.modules.sync import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/operaciones", response_model=schemas.LoteSyncResponse)
def sincronizar_operaciones(
    lote: schemas.LoteSyncRequest,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Recibe operaciones hechas sin conexión (venta de contado, reserva de cliente) y las aplica.

    Cada operación responde `ok` (con el `id_servidor` de la venta/reserva) o `conflict` (con el motivo). El `uuid`
    de la app es la clave de idempotencia: reenviarlo no duplica nada. La empresa sale del token (multi-empresa).
    """
    return service.sincronizar_lote(db, usuario, lote, request=request)


_ROLES_CONFLICTOS = ("encargado_sucursal", "administrador")


@router.get("/conflictos", response_model=list[schemas.ConflictoOut])
def listar_conflictos(
    sucursal_id: int | None = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles(*_ROLES_CONFLICTOS)),
):
    """Ventas hechas offline que quedaron `en_conflicto` por falta de stock. El encargado ve solo las de su sucursal."""
    return service.listar_conflictos(db, usuario, sucursal_id)


@router.post("/conflictos/{venta_id}/resolver", response_model=schemas.ResolverConflictoResponse)
def resolver_conflicto(
    venta_id: int,
    data: schemas.ResolverConflictoRequest,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles(*_ROLES_CONFLICTOS)),
):
    """ANULAR (no descuenta stock), AJUSTAR (otras prendas, verificando stock) o FORZAR (descuenta aunque quede negativo)."""
    return service.resolver_conflicto(db, usuario, venta_id, data, request=request)
