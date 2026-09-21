"""Modelo de datos del módulo Vestidor virtual (CU05) — historial de generaciones."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.sql import func

from app.shared.db.session import Base


class VestidorGeneracion(Base):
    __tablename__ = "vestidor_generaciones"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    imagen_resultado_url = Column(String(500), nullable=False)
    creado_en = Column(DateTime, server_default=func.now())


class VestidorJob(Base):
    """Job asíncrono de generación del vestidor virtual.

    Estados: pendiente → procesando → completado | fallido
    """

    __tablename__ = "vestidor_jobs"

    id = Column(Integer, primary_key=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False, index=True)
    estado = Column(String(20), nullable=False, default="pendiente")
    imagen_resultado_url = Column(String(1000), nullable=True)
    error = Column(Text, nullable=True)
    creado_en = Column(DateTime, server_default=func.now())
    actualizado_en = Column(DateTime, server_default=func.now(), onupdate=func.now())
