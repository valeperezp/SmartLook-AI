from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Sucursal(Base):
    __tablename__ = "sucursales"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    direccion = Column(String(255), nullable=False)
    ciudad = Column(String(100), nullable=True)
    telefono = Column(String(50), nullable=True)
    activa = Column(Boolean, default=True)


class SucursalQR(Base):
    __tablename__ = "sucursales_qr"

    id = Column(Integer, primary_key=True, index=True)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    imagen_path = Column(String(255), nullable=False)
    activo = Column(Boolean, default=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())
    desactivado_en = Column(DateTime(timezone=True), nullable=True)

    sucursal = relationship("Sucursal")
