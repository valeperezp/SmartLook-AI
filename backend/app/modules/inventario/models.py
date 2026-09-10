"""Modelo de datos del módulo Inventario."""
from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Inventario(Base):
    __tablename__ = "inventario"

    id = Column(Integer, primary_key=True, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    cantidad_disponible = Column(Integer, default=0, nullable=False)
    cantidad_reservada = Column(Integer, default=0, nullable=False)
    cantidad_vendida = Column(Integer, default=0, nullable=False)
    stock_minimo = Column(Integer, default=5, nullable=False)
    activo = Column(Boolean, default=True)

    producto = relationship("Producto")
    sucursal = relationship("Sucursal")
    talla = relationship("Talla")
    color = relationship("Color")
    movimientos = relationship("MovimientoInventario", back_populates="inventario")

    @property
    def nombre_producto(self) -> str:
        return self.producto.nombre if self.producto else ""

    @property
    def nombre_sucursal(self) -> str:
        return self.sucursal.nombre if self.sucursal else ""

    @property
    def nombre_talla(self) -> str | None:
        return self.talla.nombre if self.talla else None

    @property
    def nombre_color(self) -> str | None:
        return self.color.nombre if self.color else None

    @property
    def estado(self) -> str:
        if self.cantidad_disponible == 0:
            return "agotado"
        if self.cantidad_disponible <= self.stock_minimo:
            return "bajo"
        return "disponible"


class MovimientoInventario(Base):
    __tablename__ = "movimiento_inventario"

    id = Column(Integer, primary_key=True, index=True)
    inventario_id = Column(Integer, ForeignKey("inventario.id"), nullable=False)
    tipo = Column(String(30), nullable=False)  # entrada, salida, reserva, venta, ajuste
    cantidad = Column(Integer, nullable=False)
    motivo = Column(String(255), nullable=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    inventario = relationship("Inventario", back_populates="movimientos")
    usuario = relationship("Usuario")

    @property
    def nombre_usuario(self) -> str | None:
        return self.usuario.nombre if self.usuario else None

    @property
    def nombre_producto(self) -> str:
        return self.inventario.nombre_producto if self.inventario else ""

    @property
    def nombre_sucursal(self) -> str:
        return self.inventario.nombre_sucursal if self.inventario else ""
