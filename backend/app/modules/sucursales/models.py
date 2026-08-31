from sqlalchemy import Column, Integer, String, Boolean
from app.shared.db.session import Base


class Sucursal(Base):
    __tablename__ = "sucursales"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    direccion = Column(String(255), nullable=False)
    ciudad = Column(String(100), nullable=True)
    telefono = Column(String(50), nullable=True)
    activa = Column(Boolean, default=True)

