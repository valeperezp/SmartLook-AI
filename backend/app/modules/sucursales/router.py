"""Endpoints HTTP del módulo Sucursales (CU5). Lectura abierta, escritura admin.

Todo se resuelve dentro de una empresa: la lectura pública usa la empresa del
contexto (sesión, header X-Empresa o tienda por defecto) y la escritura la del admin.
"""
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.orm import Session

from app.modules.auth.service import empresa_contexto, require_roles
from app.modules.usuarios.models import Usuario
from app.modules.sucursales import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/sucursales", tags=["sucursales"])

admin_only = require_roles("administrador")
encargado_or_admin = require_roles("encargado_sucursal", "administrador")


@router.get("", response_model=list[schemas.SucursalOut])
def listar_sucursales(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_sucursales(db, empresa_id)


@router.get("/{sucursal_id}", response_model=schemas.SucursalOut)
def obtener_sucursal(sucursal_id: int, db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    sucursal = service.obtener_sucursal(db, sucursal_id, empresa_id)
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal


@router.post("", response_model=schemas.SucursalOut, status_code=201)
def crear_sucursal(data: schemas.SucursalCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_sucursal(db, data, admin.empresa_id, admin)


@router.put("/{sucursal_id}", response_model=schemas.SucursalOut)
def actualizar_sucursal(
    sucursal_id: int,
    data: schemas.SucursalUpdate,
    db: Session = Depends(get_db),
    admin: Usuario = Depends(admin_only),
):
    sucursal = service.actualizar_sucursal(db, sucursal_id, data, admin.empresa_id, admin)
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal


@router.delete("/{sucursal_id}", response_model=schemas.SucursalOut)
def eliminar_sucursal(sucursal_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    sucursal = service.eliminar_sucursal(db, sucursal_id, admin.empresa_id, admin)
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

    return await service.subir_qr_sucursal(db, sucursal_id, archivo, usuario.empresa_id)


@router.get("/{sucursal_id}/qr", response_model=schemas.SucursalQROut)
def obtener_qr(
    sucursal_id: int,
    db: Session = Depends(get_db),
    empresa_id: int = Depends(empresa_contexto),
):
    """Obtiene el QR activo de una sucursal (público para que el cliente lo vea)."""
    qr = service.obtener_qr_activo(db, sucursal_id, empresa_id)
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

    if not service.desactivar_qr(db, sucursal_id, usuario.empresa_id):
        raise HTTPException(status_code=404, detail="No hay QR activo")
    return None
