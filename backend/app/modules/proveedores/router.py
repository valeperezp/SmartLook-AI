"""Endpoints HTTP del módulo Proveedores. Todo protegido: solo administrador."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.proveedores import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/proveedores", tags=["proveedores"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.ProveedorOut], dependencies=[Depends(admin_only)])
def listar_proveedores(db: Session = Depends(get_db)):
    return service.listar_proveedores(db)


@router.get("/{proveedor_id}", response_model=schemas.ProveedorOut, dependencies=[Depends(admin_only)])
def obtener_proveedor(proveedor_id: int, db: Session = Depends(get_db)):
    proveedor = service.obtener_proveedor(db, proveedor_id)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor


@router.post("", response_model=schemas.ProveedorOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_proveedor(data: schemas.ProveedorCreate, db: Session = Depends(get_db)):
    return service.crear_proveedor(db, data)


@router.put("/{proveedor_id}", response_model=schemas.ProveedorOut, dependencies=[Depends(admin_only)])
def actualizar_proveedor(proveedor_id: int, data: schemas.ProveedorUpdate, db: Session = Depends(get_db)):
    proveedor = service.actualizar_proveedor(db, proveedor_id, data)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor


@router.delete("/{proveedor_id}", response_model=schemas.ProveedorOut, dependencies=[Depends(admin_only)])
def eliminar_proveedor(proveedor_id: int, db: Session = Depends(get_db)):
    proveedor = service.eliminar_proveedor(db, proveedor_id)
    if not proveedor:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return proveedor
