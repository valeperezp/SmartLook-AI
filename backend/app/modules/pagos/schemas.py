"""Esquemas Pydantic del módulo Pagos (CU19 - Stripe)."""
from datetime import datetime
from pydantic import BaseModel, ConfigDict


class PaymentIntentCreate(BaseModel):
    venta_id: int
    metodo: str = "tarjeta"


class PaymentIntentResponse(BaseModel):
    client_secret: str
    payment_intent_id: str
    monto: float
    moneda: str


class PagoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    venta_id: int
    metodo: str
    monto: float
    estado: str
    referencia_externa: str | None = None
    procesado_en: datetime
    nombre_venta: str = ""
    monto_formateado: str = ""
    comprobante_path: str | None = None
    comprobante_url: str | None = None
    confirmado_por_id: int | None = None
    confirmado_en: datetime | None = None


class PagoConfirmar(BaseModel):
    payment_intent_id: str


class PagoQRCreate(BaseModel):
    venta_id: int


class PagoConfirmarQR(BaseModel):
    aprobar: bool
    motivo_rechazo: str | None = None


class PagoPublicoOut(BaseModel):
    """Info pública de un pago (para mostrar en la página sin login)."""
    id: int
    venta_id: int
    monto: float
    monto_formateado: str
    estado: str
    nombre_sucursal: str | None = None
    ya_tiene_comprobante: bool = False


class ComprobantePublicoResponse(BaseModel):
    """Respuesta cuando el cliente sube el comprobante."""
    id: int
    venta_id: int
    monto: float
    estado: str
    mensaje: str

