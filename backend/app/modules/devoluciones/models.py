"""Modelo de datos del módulo Devoluciones (CU11).

El plazo para cambios y devoluciones es de cada empresa (multi-empresa). Vive en una tabla propia y no en `empresas`
porque la base es compartida y `create_all` no agrega columnas a tablas que ya existen (sí crea esta tabla sola al
arrancar). Una empresa sin fila usa `PLAZO_POR_DEFECTO_DIAS`.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ConfiguracionDevoluciones(Base):
    __tablename__ = "configuracion_devoluciones"

    empresa_id = Column(Integer, ForeignKey("empresas.id"), primary_key=True)
    plazo_dias = Column(Integer, nullable=False, default=7)
    actualizado_en = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
