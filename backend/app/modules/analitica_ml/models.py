"""Modelos de Machine Learning entrenados por empresa (CU15, RN-29)."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, LargeBinary, String
from sqlalchemy.orm import deferred
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
    archivo = Column(String(255), nullable=False)  # copia local del modelo serializado con joblib
    # El modelo serializado (joblib comprimido) también se guarda en la base: así queda disponible
    # para cualquier instalación del backend que use la misma base compartida (RF-23).
    # deferred: el dashboard no descarga los bytes del modelo, solo sus resultados.
    contenido = deferred(Column(LargeBinary, nullable=True))
    entrenado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    entrenado_en = Column(DateTime(timezone=True), server_default=func.now())
