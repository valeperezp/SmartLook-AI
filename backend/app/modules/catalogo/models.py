"""Modelo de datos del módulo Catálogo (prendas de vestir)."""
from sqlalchemy import Column, Integer, String, Numeric, ForeignKey
from sqlalchemy.orm import relationship

from app.shared.db.session import Base


class Producto(Base):
    __tablename__ = "productos"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(String(500))
    categoria = Column(String(80), index=True)
    talla = Column(String(10))
    color = Column(String(40))
    temporada = Column(String(60))
    precio = Column(Numeric(10, 2), nullable=False)
    proveedor_id = Column(Integer, ForeignKey("proveedores.id"), nullable=True)

    # relationship() a Proveedor se define cuando exista el modelo en usuarios/proveedores
