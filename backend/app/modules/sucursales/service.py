"""Lógica de negocio del módulo Sucursales."""
import os
import uuid
from datetime import datetime, timezone
from fastapi import UploadFile, HTTPException
from sqlalchemy.orm import Session

from app.modules.sucursales import models, schemas
from app.modules.sucursales.models import Sucursal, SucursalQR
from app.shared.core.config import settings


def listar_sucursales(db: Session) -> list[models.Sucursal]:
    return db.query(models.Sucursal).order_by(models.Sucursal.id).all()


def obtener_sucursal(db: Session, sucursal_id: int) -> models.Sucursal | None:
    return db.query(models.Sucursal).filter(models.Sucursal.id == sucursal_id).first()


def crear_sucursal(db: Session, data: schemas.SucursalCreate) -> models.Sucursal:
    sucursal = models.Sucursal(**data.model_dump())
    db.add(sucursal)
    db.commit()
    db.refresh(sucursal)
    return sucursal


def actualizar_sucursal(db: Session, sucursal_id: int, data: schemas.SucursalUpdate) -> models.Sucursal | None:
    sucursal = obtener_sucursal(db, sucursal_id)
    if not sucursal:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(sucursal, campo, valor)
    db.commit()
    db.refresh(sucursal)
    return sucursal


def eliminar_sucursal(db: Session, sucursal_id: int) -> models.Sucursal | None:
    sucursal = obtener_sucursal(db, sucursal_id)
    if not sucursal:
        return None
    sucursal.activa = False
    db.commit()
    db.refresh(sucursal)
    return sucursal


ALLOWED_IMAGE_TYPES = {"image/png", "image/jpeg", "image/jpg", "image/webp"}
MAX_QR_SIZE = 5 * 1024 * 1024  # 5 MB


async def subir_qr_sucursal(db: Session, sucursal_id: int, archivo: UploadFile) -> dict:
    """Sube un QR para la sucursal, desactivando el anterior."""
    # Validar tipo
    if archivo.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Formato no permitido. Usá PNG, JPG o WEBP")
    
    # Leer contenido y validar tamaño
    contenido = await archivo.read()
    if len(contenido) > MAX_QR_SIZE:
        raise HTTPException(status_code=400, detail="El archivo supera los 5 MB")
    
    # Verificar que la sucursal existe
    sucursal = db.query(Sucursal).filter(Sucursal.id == sucursal_id).first()
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    
    # Desactivar QRs anteriores de esta sucursal
    db.query(SucursalQR).filter(
        SucursalQR.sucursal_id == sucursal_id,
        SucursalQR.activo.is_(True)
    ).update({
        "activo": False,
        "desactivado_en": datetime.now(timezone.utc)
    })
    
    # Guardar archivo
    extension = archivo.filename.split('.')[-1] if '.' in archivo.filename else 'png'
    nombre = f"sucursal_{sucursal_id}_{uuid.uuid4().hex[:8]}.{extension}"
    path_relativo = f"qr/{nombre}"
    path_absoluto = os.path.join(settings.uploads_dir, path_relativo)
    
    os.makedirs(os.path.dirname(path_absoluto), exist_ok=True)
    
    with open(path_absoluto, "wb") as f:
        f.write(contenido)
    
    # Crear registro
    qr = SucursalQR(
        sucursal_id=sucursal_id,
        imagen_path=path_relativo,
        activo=True,
    )
    db.add(qr)
    db.commit()
    db.refresh(qr)
    
    return {
        "id": qr.id,
        "sucursal_id": qr.sucursal_id,
        "imagen_path": qr.imagen_path,
        "activo": qr.activo,
        "creado_en": qr.creado_en,
        "desactivado_en": qr.desactivado_en,
        "imagen_url": f"{settings.uploads_base_url}/uploads/{qr.imagen_path}",
    }


def obtener_qr_activo(db: Session, sucursal_id: int) -> dict | None:
    """Obtiene el QR activo de una sucursal."""
    qr = db.query(SucursalQR).filter(
        SucursalQR.sucursal_id == sucursal_id,
        SucursalQR.activo.is_(True)
    ).first()
    
    if not qr:
        return None
    
    return {
        "id": qr.id,
        "sucursal_id": qr.sucursal_id,
        "imagen_path": qr.imagen_path,
        "activo": qr.activo,
        "creado_en": qr.creado_en,
        "desactivado_en": qr.desactivado_en,
        "imagen_url": f"{settings.uploads_base_url}/uploads/{qr.imagen_path}",
    }


def desactivar_qr(db: Session, sucursal_id: int) -> bool:
    """Desactiva el QR activo de la sucursal."""
    qr = db.query(SucursalQR).filter(
        SucursalQR.sucursal_id == sucursal_id,
        SucursalQR.activo.is_(True)
    ).first()
    
    if not qr:
        return False
    
    qr.activo = False
    qr.desactivado_en = datetime.now(timezone.utc)
    db.commit()
    return True
