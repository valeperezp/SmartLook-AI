"""Modelos de Machine Learning entrenados por empresa (CU15, RN-29)."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ModeloML(Base):
    __tablename__ = "modelos_ml"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    tipo = Column(String(20), nullable=False)  # demanda | segmentacion
    algoritmo = Column(String(60), nullable=False)
    version = Column(Integer, nullable=False)
    metricas = Column(JSON, nullable=False)
    parametros = Column(JSON, nullable=False)
    # Predicciones / segmentos ya calculados: el dashboard los muestra aunque el motor no responda.
    resultado = Column(JSON, nullable=False)
    archivo = Column(String(255), nullable=False)  # modelo serializado con joblib
    entrenado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    entrenado_en = Column(DateTime(timezone=True), server_default=func.now())
