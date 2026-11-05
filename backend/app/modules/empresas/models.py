"""Modelos multi-empresa (CU2, CU3, CU4): empresas contratantes, planes, funcionalidades y suscripciones.

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
    nombre = Column(String(150), nullable=False)  # razón social
    # Identificador corto que se usa al iniciar sesión (ej: "smartlook").
    slug = Column(String(60), unique=True, index=True, nullable=False)
    nit = Column(String(30), nullable=True, unique=True)
    email = Column(String(150), nullable=True)
    telefono = Column(String(50), nullable=True)
    direccion = Column(String(255), nullable=True)
    # RF-22: logotipo que encabeza los reportes exportados (URL pública de una imagen PNG/JPG).
    logo_url = Column(String(500), nullable=True)
    # False = suspendida (CU2 2b): sus usuarios no pueden iniciar sesión.
    activa = Column(Boolean, default=True, nullable=False)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    suscripciones = relationship(
        "Suscripcion", back_populates="empresa", order_by="Suscripcion.id.desc()"
    )

    @property
    def estado(self) -> str:
        return "activa" if self.activa else "suspendida"


class Funcionalidad(Base):
    """Funcionalidad que un plan puede habilitar (CU3), ej: reportes con IA."""
    __tablename__ = "funcionalidades"

    id = Column(Integer, primary_key=True, index=True)
    codigo = Column(String(50), unique=True, nullable=False)
    nombre = Column(String(100), nullable=False)
    descripcion = Column(String(255), nullable=True)
    activo = Column(Boolean, default=True, nullable=False)


class PlanFuncionalidad(Base):
    __tablename__ = "plan_funcionalidad"

    plan_id = Column(Integer, ForeignKey("planes.id", ondelete="CASCADE"), primary_key=True)
    funcionalidad_id = Column(Integer, ForeignKey("funcionalidades.id"), primary_key=True)
    habilitado = Column(Boolean, default=True, nullable=False)

    funcionalidad = relationship("Funcionalidad")


class Plan(Base):
    __tablename__ = "planes"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(60), unique=True, nullable=False)
    descripcion = Column(String(255), nullable=True)
    precio_mensual = Column(Numeric(10, 2), nullable=False, default=0)  # precio referencial
    # CU4 paso 6: la fecha de vencimiento se calcula con esta duración.
    duracion_dias = Column(Integer, nullable=True, default=30)
    # Límites del plan. NULL = ilimitado.
    max_sucursales = Column(Integer, nullable=True)
    max_usuarios = Column(Integer, nullable=True)
    max_productos = Column(Integer, nullable=True)
    # Se mantiene sincronizado con la funcionalidad "reportes_ia" (RN-05).
    incluye_ia = Column(Boolean, default=False, nullable=False)
    activo = Column(Boolean, default=True, nullable=False)  # False = no se ofrece para nuevas contrataciones
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    plan_funcionalidades = relationship(
        "PlanFuncionalidad", cascade="all, delete-orphan", lazy="selectin"
    )

    def tiene(self, codigo: str) -> bool:
        return any(
            pf.habilitado and pf.funcionalidad.activo and pf.funcionalidad.codigo == codigo
            for pf in self.plan_funcionalidades
        )

    @property
    def funcionalidades(self) -> list[str]:
        """Códigos de las funcionalidades habilitadas."""
        return sorted(
            pf.funcionalidad.codigo for pf in self.plan_funcionalidades
            if pf.habilitado and pf.funcionalidad.activo
        )


class Suscripcion(Base):
    __tablename__ = "suscripciones"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    plan_id = Column(Integer, ForeignKey("planes.id"), nullable=False)
    # activa, suspendida, cancelada, reemplazada (= cerrada: quedó en el historial)
    estado = Column(String(20), nullable=False, default="activa")
    fecha_inicio = Column(Date, nullable=False)
    fecha_fin = Column(Date, nullable=True)  # fecha de vencimiento; NULL = sin vencimiento
    # La contratación y el pago se simulan administrativamente (CU4).
    monto_pagado = Column(Numeric(10, 2), nullable=True)
    metodo_pago_simulado = Column(String(30), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    empresa = relationship("Empresa", back_populates="suscripciones")
    plan = relationship("Plan")
