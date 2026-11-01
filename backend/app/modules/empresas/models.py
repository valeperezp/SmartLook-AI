"""Modelos multi-empresa (CU2, CU3, CU4): empresas contratantes, planes y suscripciones.

Cada empresa es un tenant: sus usuarios, sucursales y productos llevan empresa_id.
El superadmin de la plataforma no pertenece a ninguna empresa.
"""
from sqlalchemy import Boolean, Column, Date, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Empresa(Base):
    __tablename__ = "empresas"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    # Identificador corto que se usa al iniciar sesión (ej: "smartlook").
    slug = Column(String(60), unique=True, index=True, nullable=False)
    nit = Column(String(30), nullable=True)
    email = Column(String(150), nullable=True)
    telefono = Column(String(50), nullable=True)
    direccion = Column(String(255), nullable=True)
    activa = Column(Boolean, default=True, nullable=False)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    suscripciones = relationship(
        "Suscripcion", back_populates="empresa", order_by="Suscripcion.id.desc()"
    )


class Plan(Base):
    __tablename__ = "planes"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(60), unique=True, nullable=False)
    descripcion = Column(String(255), nullable=True)
    precio_mensual = Column(Numeric(10, 2), nullable=False, default=0)
    # Límites del plan. NULL = ilimitado.
    max_sucursales = Column(Integer, nullable=True)
    max_usuarios = Column(Integer, nullable=True)
    max_productos = Column(Integer, nullable=True)
    activo = Column(Boolean, default=True, nullable=False)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())


class Suscripcion(Base):
    __tablename__ = "suscripciones"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("planes.id"), nullable=False)
    # activa, suspendida, cancelada, reemplazada
    estado = Column(String(20), nullable=False, default="activa")
    fecha_inicio = Column(Date, nullable=False)
    fecha_fin = Column(Date, nullable=True)  # NULL = sin vencimiento
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    empresa = relationship("Empresa", back_populates="suscripciones")
    plan = relationship("Plan")
