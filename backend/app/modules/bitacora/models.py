"""Bitácora de acciones (CU1, CU2, CU3, CU4, CU5, CU6).

Registra quién hizo qué y cuándo: inicios de sesión, altas y cambios de empresas, planes,
suscripciones, sucursales y usuarios, e intentos rechazados por seguridad.
Nunca guarda contraseñas ni tokens (RNF-10).
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Bitacora(Base):
    __tablename__ = "bitacora"

    id = Column(Integer, primary_key=True, index=True)
    # NULL: acción de la plataforma (superadmin) o intento sin usuario identificado.
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=True, index=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True, index=True)
    accion = Column(String(60), nullable=False, index=True)  # ej: "sesion.inicio", "empresa.suspender"
    detalle = Column(String(500), nullable=True)
    ip = Column(String(60), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now(), index=True)

    usuario = relationship("Usuario")
    empresa = relationship("Empresa")

    @property
    def nombre_usuario(self) -> str | None:
        return self.usuario.nombre if self.usuario else None

    @property
    def email_usuario(self) -> str | None:
        return self.usuario.email if self.usuario else None

    @property
    def nombre_empresa(self) -> str | None:
        return self.empresa.nombre if self.empresa else None
