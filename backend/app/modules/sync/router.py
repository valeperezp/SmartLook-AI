"""Endpoint de sincronización de la app móvil offline."""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.modules.auth.service import get_current_user
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
