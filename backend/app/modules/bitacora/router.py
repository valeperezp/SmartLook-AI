"""Consulta de la bitácora: el superadmin ve la de la plataforma y el administrador la de su empresa."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import ROL_SUPERADMIN, require_roles
from app.modules.bitacora import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/bitacora", tags=["bitacora"])


@router.get("", response_model=list[schemas.BitacoraOut])
def listar(
    accion: str | None = Query(None, description="Prefijo de la acción, ej: 'sesion' o 'empresa.'"),
    limite: int = Query(200, ge=1, le=500),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles(ROL_SUPERADMIN, "administrador")),
):
    return service.listar(db, usuario, accion, limite)
