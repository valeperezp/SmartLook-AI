"""Endpoints HTTP del módulo ia (CU06 — recibir recomendaciones, CU20 — analizar preferencias)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.ia import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/ia", tags=["ia"])

solo_cliente = require_roles("cliente")


@router.get("/preferencias", response_model=schemas.PerfilPreferencias)
def obtener_preferencias(
    usuario: Usuario = Depends(solo_cliente),
    db: Session = Depends(get_db),
):
    """CU20: perfil de preferencias derivado del historial de reservas del cliente autenticado."""
    return service.analizar_preferencias(db, cliente_id=usuario.id)


@router.get("/recomendaciones", response_model=list[schemas.ProductoRecomendado])
def obtener_recomendaciones(
    limit: int = Query(8, ge=1, le=20),
    usuario: Usuario = Depends(solo_cliente),
    db: Session = Depends(get_db),
):
    """CU06: productos recomendados para el cliente autenticado."""
    return service.generar_recomendaciones(db, cliente_id=usuario.id, limit=limit)
