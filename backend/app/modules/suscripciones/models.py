"""Modelo de datos del módulo Suscripciones de stock (CU16 — "Avísame cuando llegue").

Un cliente pide que le avisen cuando una prenda agotada vuelva a tener stock. La suscripción queda `pendiente` hasta que
entra stock de esa variante (entrada de inventario, ajuste, transferencia recibida, devolución...): entonces el servidor la
pasa a `notificado` y el cliente la ve en sus notificaciones.

`talla_id`, `color_id` y `sucursal_id` en NULL significan "cualquiera". Todo lleva `empresa_id` (multi-empresa).
"""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from app.shared.db.session import Base

ESTADO_PENDIENTE = "pendiente"
ESTADO_NOTIFICADO = "notificado"


class SuscripcionStock(Base):
    __tablename__ = "suscripciones_stock"
    __table_args__ = (UniqueConstraint("empresa_id", "uuid", name="ux_suscripciones_stock_empresa_uuid"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    uuid = Column(String(64), nullable=True)  # id local de la app (idempotencia al reenviar una suscripción hecha sin red)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False, index=True)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=True)
    estado = Column(String(20), nullable=False, default=ESTADO_PENDIENTE, index=True)  # pendiente | notificado
    fecha = Column(DateTime(timezone=True), server_default=func.now())  # cuándo se suscribió
    notificado_en = Column(DateTime(timezone=True), nullable=True)  # cuándo llegó el stock
    visto = Column(Boolean, nullable=False, default=False)  # el cliente ya vio el aviso
