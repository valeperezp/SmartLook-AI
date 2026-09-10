"""Modelo de datos del módulo Reservas."""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Reserva(Base):
    __tablename__ = "reservas"

    id = Column(Integer, primary_key=True, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    estado = Column(String(30), default="pendiente")  # pendiente, confirmada, atendida, cancelada
    horario_aproximado = Column(DateTime, nullable=True)
    creada_en = Column(DateTime(timezone=True), server_default=func.now())

    items = relationship("ReservaItem", back_populates="reserva", cascade="all, delete-orphan")
    sucursal = relationship("Sucursal")
    cliente = relationship("Usuario")

    @property
    def nombre_sucursal(self) -> str | None:
        return self.sucursal.nombre if self.sucursal else None

    @property
    def total_items(self) -> int:
        return len(self.items) if self.items else 0

    @property
    def total_unidades(self) -> int:
        return sum(item.cantidad for item in self.items) if self.items else 0

    @property
    def total_estimado(self) -> float:
        return sum(item.cantidad * item.precio_unitario for item in self.items) if self.items else 0.0



class ReservaItem(Base):
    __tablename__ = "reserva_items"

    id = Column(Integer, primary_key=True, index=True)
    reserva_id = Column(Integer, ForeignKey("reservas.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    cantidad = Column(Integer, nullable=False, default=1)

    reserva = relationship("Reserva", back_populates="items")
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
    def precio_unitario(self) -> float:
        return float(self.producto.precio) if self.producto else 0.0
