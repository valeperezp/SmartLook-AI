from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.modules.proveedores.models import Proveedor
from app.modules.sucursales.models import Sucursal
from app.shared.db.session import Base


class Usuario(Base):
    __tablename__ = "usuarios"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    email = Column(String(150), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=True)
    rol = Column(String(50), default="cliente")
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=True)
    proveedor_id = Column(Integer, ForeignKey("proveedores.id"), nullable=True)
    activo = Column(Boolean, default=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    sucursal = relationship("Sucursal")
    proveedor = relationship("Proveedor")

    @property
    def sucursal_nombre(self) -> str | None:
        return self.sucursal.nombre if self.sucursal else None

    @property
    def proveedor_nombre(self) -> str | None:
        return self.proveedor.nombre if self.proveedor else None
