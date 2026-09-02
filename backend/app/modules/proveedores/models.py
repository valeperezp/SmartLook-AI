"""Modelo de datos del módulo Proveedores."""
from sqlalchemy import Column, Integer, String, Boolean
from app.shared.db.session import Base


class Proveedor(Base):
    __tablename__ = "proveedores"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    contacto = Column(String(100), nullable=True)
    telefono = Column(String(50), nullable=True)
    email = Column(String(150), nullable=True)
    activo = Column(Boolean, default=True)
