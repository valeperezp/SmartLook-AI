"""Modelo de datos del módulo Pagos (CU19 - Stripe + QR)."""
from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Pago(Base):
    __tablename__ = "pagos"

    id = Column(Integer, primary_key=True, index=True)
    venta_id = Column(Integer, ForeignKey("ventas.id"), nullable=False)
    metodo = Column(String(30), nullable=False)
    monto = Column(Numeric(10, 2), nullable=False)
    estado = Column(String(30), default="pendiente")
    referencia_externa = Column(String(150), nullable=True)
    procesado_en = Column(DateTime(timezone=True), server_default=func.now())

    comprobante_path = Column(String(255), nullable=True)
    confirmado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    confirmado_en = Column(DateTime(timezone=True), nullable=True)

    venta = relationship("Venta")
    confirmado_por = relationship("Usuario", foreign_keys=[confirmado_por_id])

    @property
    def nombre_venta(self) -> str:
        return f"Venta #{self.venta_id}" if self.venta_id else ""

    @property
    def monto_formateado(self) -> str:
        return f"${float(self.monto):.2f}"

    @property
    def comprobante_url(self) -> str | None:
        if not self.comprobante_path:
            return None
        from app.shared.core.config import settings
        return f"{settings.uploads_base_url}/uploads/{self.comprobante_path}"
