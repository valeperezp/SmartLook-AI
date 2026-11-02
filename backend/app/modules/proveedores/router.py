"""Endpoints HTTP del módulo Proveedores. Solo administrador, dentro de su empresa."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.proveedores import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/proveedores", tags=["proveedores"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.ProveedorOut])
def listar_proveedores(db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.listar_proveedores(db, admin.empresa_id)


@router.get("/{proveedor_id}", response_model=schemas.ProveedorOut)
def obtener_proveedor(proveedor_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    proveedor = service.obtener_proveedor(db, proveedor_id, admin.empresa_id)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor


@router.post("", response_model=schemas.ProveedorOut, status_code=201)
def crear_proveedor(data: schemas.ProveedorCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_proveedor(db, data, admin.empresa_id)


@router.put("/{proveedor_id}", response_model=schemas.ProveedorOut)
def actualizar_proveedor(
    proveedor_id: int, data: schemas.ProveedorUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    proveedor = service.actualizar_proveedor(db, proveedor_id, data, admin.empresa_id)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor


@router.delete("/{proveedor_id}", response_model=schemas.ProveedorOut)
def eliminar_proveedor(proveedor_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    proveedor = service.eliminar_proveedor(db, proveedor_id, admin.empresa_id)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor
