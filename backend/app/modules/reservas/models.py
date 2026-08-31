"""Modelo de datos del módulo Reservas."""
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
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
