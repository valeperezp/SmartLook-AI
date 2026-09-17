"""Modelo de datos del módulo Promociones (CU12)."""
from sqlalchemy import Column, Integer, String, Numeric, Date, Boolean, ForeignKey
from sqlalchemy.orm import relationship

from app.shared.db.session import Base


class Promocion(Base):
    __tablename__ = "promociones"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(String(500), nullable=True)
    tipo = Column(String(30), nullable=False)  # 'porcentaje' | 'monto_fijo'
    valor = Column(Numeric(10, 2), nullable=False)
    fecha_inicio = Column(Date, nullable=False)
    fecha_fin = Column(Date, nullable=False)
    activo = Column(Boolean, default=True)

    productos = relationship("PromocionProducto", back_populates="promocion", cascade="all, delete-orphan")

    @property
    def total_productos(self) -> int:
        return len(self.productos) if self.productos else 0


class PromocionProducto(Base):
    __tablename__ = "promociones_productos"

    id = Column(Integer, primary_key=True, index=True)
    promocion_id = Column(Integer, ForeignKey("promociones.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)

    promocion = relationship("Promocion", back_populates="productos")
    producto = relationship("Producto")

    @property
    def nombre_producto(self) -> str:
        return self.producto.nombre if self.producto else ""

    @property
    def precio_producto(self) -> float:
        return float(self.producto.precio) if self.producto else 0.0
