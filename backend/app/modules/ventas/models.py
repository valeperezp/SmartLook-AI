"""Modelo de datos del módulo Ventas (CU17 + CU04)."""
from sqlalchemy import Column, Integer, String, Numeric, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Venta(Base):
    __tablename__ = "ventas"

    id = Column(Integer, primary_key=True, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    cajero_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    canal = Column(String(30), default="presencial")  # presencial, online
    estado = Column(String(30), default="completada")  # pendiente, completada, cancelada
    total = Column(Numeric(10, 2), nullable=False, default=0)
    creada_en = Column(DateTime(timezone=True), server_default=func.now())

    cliente = relationship("Usuario", foreign_keys=[cliente_id])
    cajero = relationship("Usuario", foreign_keys=[cajero_id])
    sucursal = relationship("Sucursal")
    items = relationship("VentaItem", back_populates="venta", cascade="all, delete-orphan")

    @property
    def nombre_sucursal(self) -> str | None:
        return self.sucursal.nombre if self.sucursal else None

    @property
    def nombre_cajero(self) -> str | None:
        return self.cajero.nombre if self.cajero else None

    @property
    def nombre_cliente(self) -> str | None:
        return self.cliente.nombre if self.cliente else "Cliente presencial"

    @property
    def total_items(self) -> int:
        return sum(i.cantidad for i in self.items)

    @property
    def total_unidades(self) -> int:
        return sum(i.cantidad for i in self.items)


class VentaItem(Base):
    __tablename__ = "venta_items"

    id = Column(Integer, primary_key=True, index=True)
    venta_id = Column(Integer, ForeignKey("ventas.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    cantidad = Column(Integer, nullable=False)
    precio_unitario = Column(Numeric(10, 2), nullable=False)

    venta = relationship("Venta", back_populates="items")
    producto = relationship("Producto")
    talla = relationship("Talla")
    color = relationship("Color")

    @property
    def nombre_producto(self) -> str:
        return self.producto.nombre if self.producto else ""

    @property
    def nombre_talla(self) -> str | None:
        return self.talla.nombre if self.talla else None

    @property
    def nombre_color(self) -> str | None:
        return self.color.nombre if self.color else None

    @property
    def subtotal(self) -> float:
        return float(self.precio_unitario) * self.cantidad
