"""Endpoints HTTP del módulo Sucursales. Lectura abierta, escritura admin."""
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.modules.sucursales import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/sucursales", tags=["sucursales"])

admin_only = require_roles("administrador")
encargado_or_admin = require_roles("encargado_sucursal", "administrador")


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


@router.post("/{sucursal_id}/qr", response_model=schemas.SucursalQROut, status_code=201)
async def subir_qr(
    sucursal_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Sube el QR de una sucursal. Solo encargado de esa sucursal o admin."""
    # Si es encargado, validar que sea SU sucursal
    if usuario.rol == "encargado_sucursal" and usuario.sucursal_id != sucursal_id:
        raise HTTPException(status_code=403, detail="Solo podés subir QR de tu sucursal")
    
    return await service.subir_qr_sucursal(db, sucursal_id, archivo)


@router.get("/{sucursal_id}/qr", response_model=schemas.SucursalQROut)
def obtener_qr(
    sucursal_id: int,
    db: Session = Depends(get_db),
):
    """Obtiene el QR activo de una sucursal (público para que el cliente lo vea)."""
    qr = service.obtener_qr_activo(db, sucursal_id)
    if not qr:
        raise HTTPException(status_code=404, detail="La sucursal no tiene QR configurado")
    return qr


@router.delete("/{sucursal_id}/qr", status_code=204)
def desactivar_qr(
    sucursal_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(encargado_or_admin),
):
    """Desactiva el QR activo de la sucursal."""
    if usuario.rol == "encargado_sucursal" and usuario.sucursal_id != sucursal_id:
        raise HTTPException(status_code=403, detail="Solo podés desactivar QR de tu sucursal")
    
    if not service.desactivar_qr(db, sucursal_id):
        raise HTTPException(status_code=404, detail="No hay QR activo")
    return None
