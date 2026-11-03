"""Historial de reportes solicitados (CU14, paso 10)."""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ReporteHistorial(Base):
    __tablename__ = "reportes_historial"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    solicitud = Column(String(500), nullable=True)  # texto o dictado; None si fue un reporte convencional
    origen = Column(String(10), nullable=False)  # ia | manual
    tipo = Column(String(40), nullable=False)
    # Intención validada: tipo, fechas, ids de sucursales/categorías/productos, límite y gráfico.
    intencion = Column(JSON, nullable=False)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())
