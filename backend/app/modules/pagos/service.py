"""Lógica de negocio del módulo Pagos (CU19 - Stripe en modo test)."""
from decimal import ROUND_HALF_UP, Decimal

import stripe
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.pagos import models, schemas
from app.modules.ventas.models import Venta
from app.shared.core.config import settings
from app.shared.utils.imagenes import validar_imagen


def _inicializar_stripe():
    """Configura la API key de Stripe desde settings."""
    if not settings.stripe_secret_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Stripe no está configurado. Falta STRIPE_SECRET_KEY en .env",
        )
    stripe.api_key = settings.stripe_secret_key


def crear_payment_intent(db: Session, data: schemas.PaymentIntentCreate) -> dict:
    """Crea un PaymentIntent en Stripe para una venta."""
    _inicializar_stripe()

    venta = db.query(Venta).filter(Venta.id == data.venta_id).first()
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    if venta.estado in ("cancelada", "anulada", "en_conflicto"):
        raise HTTPException(status_code=400, detail="No se puede pagar una venta cancelada, anulada o en conflicto de stock")

    # Decimal evita el error binario de float (19.99 * 100 = 1998.999...).
    monto_centavos = int((Decimal(str(venta.total)) * 100).to_integral_value(ROUND_HALF_UP))

    try:
        intent = stripe.PaymentIntent.create(
            amount=monto_centavos,
            currency="usd",
            metadata={"venta_id": str(venta.id), "metodo": data.metodo},
            automatic_payment_methods={"enabled": True},
        )
    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=f"Error de Stripe: {str(e)}")

    return {
        "client_secret": intent.client_secret,
        "payment_intent_id": intent.id,
        "monto": float(venta.total),
        "moneda": "usd",
    }


def confirmar_pago(db: Session, data: schemas.PagoConfirmar) -> models.Pago:
    """Confirma el pago consultando el PaymentIntent a Stripe y guarda el Pago."""
    # NOTE: Las ventas online pendientes sin pago completado no expiran automáticamente
    # en esta fase. Se requiere una tarea en background/cron para cancelar ventas
    # pendientes tras una ventana de tiempo definida (deuda técnica conocida).
    _inicializar_stripe()

    try:
        intent = stripe.PaymentIntent.retrieve(data.payment_intent_id)
    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=f"Error de Stripe: {str(e)}")

    metadata = intent.metadata.to_dict() if hasattr(intent.metadata, "to_dict") else intent.metadata
    venta_id = int(metadata.get("venta_id", 0))
    if not venta_id:
        raise HTTPException(status_code=400, detail="PaymentIntent sin venta_id")

    # Se bloquea la fila de la venta: dos confirmaciones simultaneas del mismo pago se serializan
    # y la segunda ya encuentra el Pago que creo la primera.
    venta = db.query(Venta).filter(Venta.id == venta_id).with_for_update().populate_existing().first()
    if not venta:
        raise HTTPException(status_code=404, detail="Venta asociada no encontrada")

    # Idempotencia: un PaymentIntent solo genera un Pago (referencia_externa empieza por el id del intent;
    # este mismo flujo le agrega el sufijo " - FALLO STOCK: ..."). Si ya esta resuelto, se devuelve tal cual.
    pago_existente = (
        db.query(models.Pago)
        .filter(models.Pago.referencia_externa.startswith(intent.id, autoescape=True))
        .order_by(models.Pago.id)
        .first()
    )
    if pago_existente and pago_existente.estado in ("completado", "fallido"):
        return pago_existente

    # Un Pago 'pendiente' previo (3DS / processing) se actualiza; si no hay ninguno, se crea.
    pago = pago_existente or models.Pago(
        venta_id=venta_id,
        metodo=metadata.get("metodo", "tarjeta"),
        monto=float(venta.total),
        referencia_externa=intent.id,
    )

    if intent.status == "succeeded":
        pago.estado = "completado"
        db.add(pago)
        db.commit()
        db.refresh(pago)

        # Si es una venta online pendiente, completar la venta y descontar stock
        if venta.canal == "online" and venta.estado == "pendiente":
            from app.modules.ventas.service import completar_venta_y_descontar_stock

            try:
                completar_venta_y_descontar_stock(db, venta.id)
            except HTTPException as e:
                pago.estado = "fallido"
                pago.referencia_externa = f"{intent.id} - FALLO STOCK: {e.detail}"
                venta.estado = "cancelada"
                db.commit()
                raise e
    elif intent.status in ("requires_payment_method", "canceled"):
        # Fallo definitivo del cobro: se cancela la venta online que siga pendiente.
        pago.estado = "fallido"
        db.add(pago)
        if venta.canal == "online" and venta.estado == "pendiente":
            venta.estado = "cancelada"
        db.commit()
        db.refresh(pago)
    else:
        # processing / requires_action (3DS) / otros: el cobro sigue en curso; no se cancela nada.
        pago.estado = "pendiente"
        db.add(pago)
        db.commit()
        db.refresh(pago)

    return pago


def listar_pagos_por_venta(db: Session, venta_id: int) -> list[models.Pago]:
    return (
        db.query(models.Pago)
        .options(joinedload(models.Pago.venta))
        .filter(models.Pago.venta_id == venta_id)
        .order_by(models.Pago.procesado_en.desc())
        .all()
    )


def obtener_pago(db: Session, pago_id: int) -> models.Pago | None:
    return (
        db.query(models.Pago)
        .options(joinedload(models.Pago.venta))
        .filter(models.Pago.id == pago_id)
        .first()
    )


import os
import uuid
from fastapi import UploadFile


ALLOWED_IMAGE_TYPES = {"image/png", "image/jpeg", "image/jpg", "image/webp"}
MAX_COMPROBANTE_SIZE = 10 * 1024 * 1024  # 10 MB


def crear_pago_qr(db: Session, venta_id: int) -> models.Pago:
    """Crea un pago pendiente por QR para una venta."""
    venta = db.query(Venta).filter(Venta.id == venta_id).first()
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    if venta.estado in ("cancelada", "anulada", "en_conflicto"):
        raise HTTPException(status_code=400, detail="No se puede pagar una venta cancelada, anulada o en conflicto de stock")

    pago = models.Pago(
        venta_id=venta_id,
        metodo="qr",
        monto=float(venta.total),
        estado="pendiente",
    )
    db.add(pago)
    db.commit()
    db.refresh(pago)
    return pago


def crear_pago_efectivo(db: Session, venta_id: int) -> models.Pago:
    """Registra un pago pendiente en efectivo — se cobra al retirar en la sucursal."""
    venta = db.query(Venta).filter(Venta.id == venta_id).first()
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    if venta.estado in ("cancelada", "anulada", "en_conflicto"):
        raise HTTPException(status_code=400, detail="No se puede pagar una venta cancelada, anulada o en conflicto de stock")

    pago = models.Pago(
        venta_id=venta_id,
        metodo="efectivo",
        monto=float(venta.total),
        estado="pendiente",
    )
    db.add(pago)
    db.commit()
    db.refresh(pago)
    return pago


async def subir_comprobante(db: Session, pago_id: int, archivo: UploadFile) -> models.Pago:
    """Sube el comprobante de un pago QR."""
    pago = db.query(models.Pago).filter(models.Pago.id == pago_id).first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.metodo != "qr":
        raise HTTPException(status_code=400, detail="Este pago no es por QR")
    
    if pago.estado != "pendiente":
        raise HTTPException(status_code=400, detail="Este pago ya fue procesado")
    
    if archivo.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Formato no permitido. Usá PNG, JPG o WEBP")
    
    contenido = await archivo.read()
    # Tamano y magic bytes (el content-type declarado es falsificable); la extension sale del contenido real
    _, extension = validar_imagen(contenido, MAX_COMPROBANTE_SIZE)
    
    nombre = f"pago_{pago_id}_{uuid.uuid4().hex[:8]}.{extension}"
    path_relativo = f"comprobantes/{nombre}"
    path_absoluto = os.path.join(settings.uploads_dir, path_relativo)
    
    os.makedirs(os.path.dirname(path_absoluto), exist_ok=True)
    
    with open(path_absoluto, "wb") as f:
        f.write(contenido)
    
    pago.comprobante_path = path_relativo
    db.commit()
    db.refresh(pago)
    
    return pago


def confirmar_pago_qr(db: Session, pago_id: int, aprobar: bool, usuario_id: int, motivo: str | None = None) -> models.Pago:
    """Confirma o rechaza un pago QR."""
    from datetime import datetime, timezone
    
    # Se bloquea la fila del pago: dos cajeros aprobando a la vez se serializan y el segundo ve el estado ya cambiado.
    pago = db.query(models.Pago).filter(models.Pago.id == pago_id).with_for_update().populate_existing().first()
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.metodo != "qr":
        raise HTTPException(status_code=400, detail="Este pago no es por QR")
    
    if pago.estado != "pendiente":
        raise HTTPException(status_code=409, detail="Este pago ya fue procesado")
    
    if not pago.comprobante_path:
        raise HTTPException(status_code=400, detail="El pago no tiene comprobante subido")
    
    venta = db.query(Venta).filter(Venta.id == pago.venta_id).first()

    # Cajero / encargado solo gestionan pagos de su propia sucursal; el administrador no tiene restriccion.
    from app.modules.usuarios.models import Usuario

    usuario = db.query(Usuario).filter(Usuario.id == usuario_id).first()
    if usuario and usuario.rol in ("cajero", "encargado_sucursal"):
        if venta is None or venta.sucursal_id != usuario.sucursal_id:
            raise HTTPException(status_code=403, detail="No tiene permisos para gestionar pagos de otra sucursal")

    pago.confirmado_por_id = usuario_id
    pago.confirmado_en = datetime.now(timezone.utc)

    if aprobar:
        pago.estado = "completado"
        db.commit()
        db.refresh(pago)

        # Si es una venta online pendiente, completar la venta y descontar stock
        if venta and venta.canal == "online" and venta.estado == "pendiente":
            from app.modules.ventas.service import completar_venta_y_descontar_stock

            try:
                completar_venta_y_descontar_stock(db, venta.id)
            except HTTPException as e:
                pago.estado = "fallido"
                pago.referencia_externa = f"FALLO STOCK: {e.detail}"
                venta.estado = "cancelada"
                db.commit()
                raise e
    else:
        pago.estado = "fallido"
        if motivo:
            pago.referencia_externa = f"RECHAZADO: {motivo[:100]}"
        if venta and venta.canal == "online":
            venta.estado = "cancelada"
        db.commit()
        db.refresh(pago)
    
    return pago


def listar_pagos_pendientes_qr(db: Session, sucursal_id: int | None = None) -> list[models.Pago]:
    """Lista los pagos QR pendientes de verificación."""
    from app.modules.ventas.models import Venta
    
    query = (
        db.query(models.Pago)
        .join(models.Pago.venta)
        .options(joinedload(models.Pago.venta))
        .filter(
            models.Pago.metodo == "qr",
            models.Pago.estado == "pendiente",
            models.Pago.comprobante_path.isnot(None),
        )
    )
    
    if sucursal_id:
        query = query.filter(Venta.sucursal_id == sucursal_id)
    
    return query.order_by(models.Pago.procesado_en.desc()).all()


def obtener_pago_publico(db: Session, pago_id: int) -> dict:
    """Obtiene info pública de un pago QR (sin login)."""
    from app.modules.ventas.models import Venta
    
    pago = (
        db.query(models.Pago)
        .options(joinedload(models.Pago.venta).joinedload(Venta.sucursal))
        .filter(models.Pago.id == pago_id)
        .first()
    )
    
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.metodo != "qr":
        raise HTTPException(status_code=400, detail="Este pago no es por QR")
    
    venta = pago.venta
    nombre_sucursal = None
    if venta and venta.sucursal:
        nombre_sucursal = venta.sucursal.nombre
    
    return {
        "id": pago.id,
        "venta_id": pago.venta_id,
        "monto": float(pago.monto),
        "monto_formateado": f"${float(pago.monto):.2f}",
        "estado": pago.estado,
        "nombre_sucursal": nombre_sucursal,
        "ya_tiene_comprobante": pago.comprobante_path is not None,
    }


async def subir_comprobante_publico(db: Session, pago_id: int, archivo: UploadFile) -> dict:
    """Sube el comprobante de un pago QR sin requerir login."""
    pago = db.query(models.Pago).filter(models.Pago.id == pago_id).first()
    
    if not pago:
        raise HTTPException(status_code=404, detail="Pago no encontrado")
    
    if pago.metodo != "qr":
        raise HTTPException(status_code=400, detail="Este pago no es por QR")
    
    if pago.estado != "pendiente":
        raise HTTPException(status_code=400, detail="Este pago ya fue procesado")
    
    if pago.comprobante_path is not None:
        raise HTTPException(status_code=400, detail="Este pago ya tiene un comprobante")
    
    if archivo.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="Formato no permitido. Usá PNG, JPG o WEBP")
    
    contenido = await archivo.read()
    # Tamano y magic bytes (el content-type declarado es falsificable); la extension sale del contenido real
    _, extension = validar_imagen(contenido, MAX_COMPROBANTE_SIZE)
    
    nombre = f"pago_{pago_id}_{uuid.uuid4().hex[:8]}.{extension}"
    path_relativo = f"comprobantes/{nombre}"
    path_absoluto = os.path.join(settings.uploads_dir, path_relativo)
    
    os.makedirs(os.path.dirname(path_absoluto), exist_ok=True)
    
    with open(path_absoluto, "wb") as f:
        f.write(contenido)
    
    pago.comprobante_path = path_relativo
    db.commit()
    db.refresh(pago)
    
    return {
        "id": pago.id,
        "venta_id": pago.venta_id,
        "monto": float(pago.monto),
        "estado": pago.estado,
        "mensaje": "Comprobante recibido. Esperá la verificación del cajero.",
    }

