"""Endpoints HTTP del módulo Promociones (CU12)."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.promociones import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/promociones", tags=["promociones"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.PromocionOut])
def listar_promociones(
    solo_activas: bool = False,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Lista todas las promociones (admin)."""
    return service.listar_promociones(db, solo_activas)


@router.get("/{promocion_id}", response_model=schemas.PromocionOut)
def obtener_promocion(
    promocion_id: int,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Obtiene una promoción por ID."""
    promocion = service.obtener_promocion(db, promocion_id)
    if not promocion:
        raise HTTPException(status_code=404, detail="Promoción no encontrada")
    return promocion


@router.post("", response_model=schemas.PromocionOut, status_code=201)
def crear_promocion(
    data: schemas.PromocionCreate,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Crea una nueva promoción."""
    return service.crear_promocion(db, data)


@router.put("/{promocion_id}", response_model=schemas.PromocionOut)
def actualizar_promocion(
    promocion_id: int,
    data: schemas.PromocionUpdate,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Actualiza una promoción existente."""
    promocion = service.actualizar_promocion(db, promocion_id, data)
    if not promocion:
        raise HTTPException(status_code=404, detail="Promoción no encontrada")
    return promocion


@router.delete("/{promocion_id}", response_model=schemas.PromocionOut)
def eliminar_promocion(
    promocion_id: int,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Desactiva una promoción (soft-delete)."""
    promocion = service.eliminar_promocion(db, promocion_id)
    if not promocion:
        raise HTTPException(status_code=404, detail="Promoción no encontrada")
    return promocion


@router.patch("/{promocion_id}/reactivar", response_model=schemas.PromocionOut)
def reactivar_promocion(
    promocion_id: int,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Reactiva una promoción desactivada."""
    promocion = service.reactivar_promocion(db, promocion_id)
    if not promocion:
        raise HTTPException(status_code=404, detail="Promoción no encontrada")
    return promocion


@router.put("/{promocion_id}/productos", response_model=schemas.PromocionOut)
def actualizar_productos(
    promocion_id: int,
    data: schemas.PromocionProductosUpdate,
    db: Session = Depends(get_db),
    usuario=Depends(admin_only),
):
    """Actualiza la lista de productos asociados a una promoción."""
    promocion = service.actualizar_productos(db, promocion_id, data)
    if not promocion:
        raise HTTPException(status_code=404, detail="Promoción no encontrada")
    return promocion
