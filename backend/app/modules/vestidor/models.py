"""Modelo de datos del módulo Vestidor virtual (CU05) — historial de generaciones."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.sql import func

from app.shared.db.session import Base


class VestidorGeneracion(Base):
    __tablename__ = "vestidor_generaciones"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    imagen_resultado_url = Column(String(500), nullable=False)
    creado_en = Column(DateTime, server_default=func.now())
