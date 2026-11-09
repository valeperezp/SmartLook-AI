"""Modelo de datos del módulo Devoluciones (CU11 + reembolsos de pedidos cancelados).

El plazo para cambios y devoluciones es de cada empresa (multi-empresa). Vive en una tabla propia y no en `empresas`
porque la base es compartida y `create_all` no agrega columnas a tablas que ya existen (sí crea esta tabla sola al
arrancar). Una empresa sin fila usa `PLAZO_POR_DEFECTO_DIAS`.

`Reembolso` es la devolución de DINERO de un pedido cancelado (una reserva o una venta). Es una tabla nueva por la misma
razón (la base compartida no se altera) y porque `devoluciones` (cambios de prendas) exige una venta: una reserva no la tiene.
"""
from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ConfiguracionDevoluciones(Base):
    __tablename__ = "configuracion_devoluciones"

    empresa_id = Column(Integer, ForeignKey("empresas.id"), primary_key=True)
    plazo_dias = Column(Integer, nullable=False, default=7)
    actualizado_en = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Reembolso(Base):
    """Devolución de dinero de un pedido cancelado. Una sola por reserva o venta (idempotente).

    El cliente adjunta su QR bancario (`qr_devolucion_path`) y el personal le transfiere el dinero y lo marca `reembolsado`;
    en ese momento el pedido pasa a `reembolsada`. Todo se valida contra la empresa del usuario (multi-empresa).
    """

    __tablename__ = "reembolsos"
    __table_args__ = (
        UniqueConstraint("reserva_id", name="ux_reembolsos_reserva"),
        UniqueConstraint("venta_id", name="ux_reembolsos_venta"),
        CheckConstraint(
            "(reserva_id IS NOT NULL AND venta_id IS NULL) OR (reserva_id IS NULL AND venta_id IS NOT NULL)",
            name="ck_reembolsos_un_origen",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True, index=True)  # una venta de mostrador puede no tenerlo
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    reserva_id = Column(Integer, ForeignKey("reservas.id"), nullable=True, index=True)
    venta_id = Column(Integer, ForeignKey("ventas.id"), nullable=True, index=True)
    monto = Column(Numeric(10, 2), nullable=False, default=0)
    estado = Column(String(20), nullable=False, default="pendiente")  # pendiente | reembolsado
    qr_devolucion_path = Column(String(255), nullable=True)  # relativo a UPLOADS_DIR
    qr_subido_en = Column(DateTime(timezone=True), nullable=True)
    procesado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    procesado_en = Column(DateTime(timezone=True), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    cliente = relationship("Usuario", foreign_keys=[cliente_id])
    sucursal = relationship("Sucursal")

    @property
    def qr_devolucion_url(self) -> str | None:
        """URL pública del QR que subió el cliente (misma base que los comprobantes de pago)."""
        if not self.qr_devolucion_path:
            return None
        from app.shared.core.config import settings
        return f"{settings.uploads_base_url}/uploads/{self.qr_devolucion_path}"

    @property
    def tiene_qr(self) -> bool:
        return bool(self.qr_devolucion_path)

    @property
    def origen(self) -> str:
        return "reserva" if self.reserva_id is not None else "venta"

    @property
    def nombre_cliente(self) -> str | None:
        return self.cliente.nombre if self.cliente else None

    @property
    def email_cliente(self) -> str | None:
        return self.cliente.email if self.cliente else None

    @property
    def nombre_sucursal(self) -> str | None:
        return self.sucursal.nombre if self.sucursal else None
