"""Endpoints HTTP del módulo Pagos (CU19 - Stripe)."""
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db
from app.modules.pagos import schemas, service

router = APIRouter(prefix="/pagos", tags=["pagos"])

cliente_or_admin = require_roles("cliente", "administrador", "cajero", "encargado_sucursal")


@router.post("/crear-intent", response_model=schemas.PaymentIntentResponse)
def crear_payment_intent(
    data: schemas.PaymentIntentCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Crea un PaymentIntent en Stripe para una venta."""
    return service.crear_payment_intent(db, data)


@router.post("/confirmar", response_model=schemas.PagoOut, status_code=201)
def confirmar_pago(
    data: schemas.PagoConfirmar,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Confirma el pago consultando el PaymentIntent y guarda el Pago."""
    return service.confirmar_pago(db, data)


@router.get("/venta/{venta_id}", response_model=list[schemas.PagoOut])
def listar_pagos_venta(
    venta_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Lista los pagos de una venta."""
    return service.listar_pagos_por_venta(db, venta_id)


@router.post("/qr", response_model=schemas.PagoOut, status_code=201)
def crear_pago_qr(
    data: schemas.PagoQRCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Crea un pago pendiente por QR para una venta."""
    return service.crear_pago_qr(db, data.venta_id)


@router.post("/{pago_id}/comprobante", response_model=schemas.PagoOut)
async def subir_comprobante(
    pago_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Sube el comprobante de un pago QR."""
    return await service.subir_comprobante(db, pago_id, archivo)


@router.patch("/{pago_id}/confirmar-qr", response_model=schemas.PagoOut)
def confirmar_pago_qr(
    pago_id: int,
    data: schemas.PagoConfirmarQR,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("cajero", "encargado_sucursal", "administrador")),
):
    """Confirma o rechaza un pago QR (solo cajero/encargado/admin)."""
    return service.confirmar_pago_qr(db, pago_id, data.aprobar, usuario.id, data.motivo_rechazo)


@router.get("/pendientes-verificacion", response_model=list[schemas.PagoOut])
def listar_pendientes_qr(
    sucursal_id: int | None = None,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("cajero", "encargado_sucursal", "administrador")),
):
    """Lista los pagos QR pendientes de verificación."""
    # Si es cajero o encargado, forzar su sucursal
    if usuario.rol in ("cajero", "encargado_sucursal"):
        sucursal_id = usuario.sucursal_id
    return service.listar_pagos_pendientes_qr(db, sucursal_id)


@router.get("/{pago_id}", response_model=schemas.PagoOut)
def obtener_pago(
    pago_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(cliente_or_admin),
):
    """Obtiene el detalle de un pago."""
    pago = service.obtener_pago(db, pago_id)
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    return pago


# =========================================================================
# ENDPOINTS PÚBLICOS (sin login) - para la página mobile de subida
# =========================================================================

@router.get("/{pago_id}/publico", response_model=schemas.PagoPublicoOut)
def obtener_pago_publico(
    pago_id: int,
    db: Session = Depends(get_db),
):
    """Obtiene info pública de un pago QR (sin login). Para la página mobile."""
    return service.obtener_pago_publico(db, pago_id)


@router.post("/{pago_id}/comprobante-publico", response_model=schemas.ComprobantePublicoResponse, status_code=201)
async def subir_comprobante_publico(
    pago_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """Sube el comprobante de un pago QR sin login. Para la página mobile del cliente."""
    return await service.subir_comprobante_publico(db, pago_id, archivo)

