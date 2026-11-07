"""Modelo de datos del módulo Fidelización (CU17).

La regla "cuánto vale un punto" es de cada empresa (multi-empresa): vive en una tabla propia, no en `empresas`, porque
la base es compartida y `create_all` no agrega columnas a tablas que ya existen (sí crea esta tabla sola al arrancar).
Una empresa sin fila usa el valor por defecto (`VALOR_PUNTO_POR_DEFECTO`).
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ConfiguracionFidelizacion(Base):
    __tablename__ = "configuracion_fidelizacion"

    empresa_id = Column(Integer, ForeignKey("empresas.id"), primary_key=True)
    # Centavos de gasto que dan 1 punto, y también cuántos centavos de descuento vale 1 punto al canjearlo.
    # 1000 = 1 punto por cada 10 Bs (y cada punto canjeado descuenta 10 Bs).
    valor_punto_centavos = Column(Integer, nullable=False, default=1000)
    actualizado_en = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
