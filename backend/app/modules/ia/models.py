"""Modelo de datos del módulo ia."""
from sqlalchemy import Column, DateTime, Integer, String
from sqlalchemy.sql import func

from app.shared.db.session import Base


class ConfiguracionIA(Base):
    """
    Configuración del proveedor de IA para el chatbot (CU21), compatible con el
    estándar de la API de OpenAI (base_url + api_key + nombre de modelo). Permite
    apuntar tanto a un modelo local (ej. Ollama) como a uno en la nube (OpenAI,
    Groq, etc.) sin cambiar código. Tabla de una sola fila (id fijo = 1).
    """
    __tablename__ = "ia_configuracion"

    id = Column(Integer, primary_key=True, default=1)
    base_url = Column(String(255), nullable=False, default="http://host.docker.internal:11434/v1")
    api_key = Column(String(255), nullable=True, default="")
    modelo = Column(String(100), nullable=False, default="llama3.2:1b")
    actualizado_en = Column(DateTime(timezone=True), onupdate=func.now(), server_default=func.now())
