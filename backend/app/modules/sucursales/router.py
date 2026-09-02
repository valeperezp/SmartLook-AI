"""Endpoints HTTP del módulo Sucursales. Lectura abierta, escritura admin."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.sucursales import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/sucursales", tags=["sucursales"])

admin_only = require_roles("administrador")


@router.get("", response_model=list[schemas.SucursalOut])
def listar_sucursales(db: Session = Depends(get_db)):
    return service.listar_sucursales(db)


@router.get("/{sucursal_id}", response_model=schemas.SucursalOut)
def obtener_sucursal(sucursal_id: int, db: Session = Depends(get_db)):
    sucursal = service.obtener_sucursal(db, sucursal_id)
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal


@router.post("", response_model=schemas.SucursalOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_sucursal(data: schemas.SucursalCreate, db: Session = Depends(get_db)):
    return service.crear_sucursal(db, data)


@router.put("/{sucursal_id}", response_model=schemas.SucursalOut, dependencies=[Depends(admin_only)])
def actualizar_sucursal(sucursal_id: int, data: schemas.SucursalUpdate, db: Session = Depends(get_db)):
    sucursal = service.actualizar_sucursal(db, sucursal_id, data)
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal


@router.delete("/{sucursal_id}", response_model=schemas.SucursalOut, dependencies=[Depends(admin_only)])
def eliminar_sucursal(sucursal_id: int, db: Session = Depends(get_db)):
    sucursal = service.eliminar_sucursal(db, sucursal_id)
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal
