"""Esquemas Pydantic del módulo Empresas (empresas, planes y suscripciones)."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

EstadoSuscripcion = Literal["activa", "suspendida", "cancelada", "reemplazada"]

MSG_LIMITE = "Ingrese un límite mayor que cero"  # CU3 6a (se valida en el servicio)


# ---------- Funcionalidades (CU3) ----------

class FuncionalidadOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    codigo: str
    nombre: str
    descripcion: str | None = None


# ---------- Planes (CU3) ----------

class PlanBase(BaseModel):
    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = None
    precio_mensual: Decimal = Field(ge=0)
    duracion_dias: int | None = Field(default=30, description="Duración de la suscripción; vacío = sin vencimiento")
    max_sucursales: int | None = None  # None = ilimitado
    max_usuarios: int | None = None
    max_productos: int | None = None


class PlanCreate(PlanBase):
    funcionalidades: list[str] = Field(default_factory=list, description="Códigos habilitados")


class PlanUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=60)
    descripcion: str | None = None
    precio_mensual: Decimal | None = Field(default=None, ge=0)
    duracion_dias: int | None = None
    max_sucursales: int | None = None
    max_usuarios: int | None = None
    max_productos: int | None = None
    activo: bool | None = None
    funcionalidades: list[str] | None = None


class PlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    descripcion: str | None = None
    precio_mensual: Decimal
    duracion_dias: int | None = None
    max_sucursales: int | None = None
    max_usuarios: int | None = None
    max_productos: int | None = None
    incluye_ia: bool
    activo: bool
    funcionalidades: list[str] = []


# ---------- Suscripciones (CU4) ----------

class SuscripcionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    empresa_id: int
    plan_id: int
    estado: str
    # Estado que se muestra (CU4 2b): vigente, vencida, suspendida, cancelada o cerrada.
    estado_mostrado: str = ""
    fecha_inicio: date
    fecha_fin: date | None = None
    monto_pagado: Decimal | None = None
    metodo_pago_simulado: str | None = None
    creado_en: datetime | None = None
    plan: PlanOut


class SuscripcionAsignar(BaseModel):
    """CU4 pasos 5 y 6: plan + fecha de inicio; el vencimiento lo calcula el sistema."""
    plan_id: int
    fecha_inicio: date | None = None  # None = hoy
    monto_pagado: Decimal | None = Field(default=None, ge=0)  # None = precio del plan
    metodo_pago_simulado: Literal["efectivo", "transferencia", "tarjeta", "qr"] = "transferencia"


class SuscripcionEstadoUpdate(BaseModel):
    estado: Literal["activa", "suspendida", "cancelada"]


class UsoRecurso(BaseModel):
    usados: int
    limite: int | None = None  # None = ilimitado


class UsoEmpresa(BaseModel):
    sucursales: UsoRecurso
    usuarios: UsoRecurso
    productos: UsoRecurso


# ---------- Empresas (CU2) ----------

class EmpresaBase(BaseModel):
    nombre: str = Field(min_length=2, max_length=150, description="Razón social")
    nit: str = Field(min_length=3, max_length=30)
    email: str = Field(min_length=5, max_length=150)
    telefono: str | None = Field(default=None, max_length=50)
    direccion: str | None = Field(default=None, max_length=255)
    logo_url: str | None = Field(default=None, max_length=500)


class AdminInicial(BaseModel):
    nombre: str = Field(min_length=2, max_length=100)
    email: str = Field(min_length=5, max_length=150)
    # Si no se indica, el sistema genera una contraseña temporal (CU2 paso 8).
    password: str | None = Field(default=None, min_length=6)


class EmpresaCreate(EmpresaBase):
    # Identificador para el login; si no se indica se arma con la razón social.
    slug: str | None = Field(default=None, min_length=2, max_length=60, pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$")
    administrador: AdminInicial
    # Opcional: el plan se puede asignar después (CU2 paso 9 → CU4).
    plan_id: int | None = None
    fecha_inicio: date | None = None


class EmpresaUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=150)
    nit: str | None = Field(default=None, min_length=3, max_length=30)
    email: str | None = Field(default=None, min_length=5, max_length=150)
    telefono: str | None = None
    direccion: str | None = None
    logo_url: str | None = Field(default=None, max_length=500)


class EmpresaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    slug: str
    nit: str | None = None
    email: str | None = None
    telefono: str | None = None
    direccion: str | None = None
    logo_url: str | None = None
    activa: bool
    estado: str
    creado_en: datetime | None = None


class EmpresaDetalle(EmpresaOut):
    suscripcion: SuscripcionOut | None = None
    suscripcion_vigente: bool
    uso: UsoEmpresa
    # RN-08: días que faltan para el vencimiento (negativo = ya venció; None = sin vencimiento).
    dias_para_vencer: int | None = None
    aviso_vencimiento: bool = False
    # RN-06: con la suscripción vencida la empresa solo puede consultar.
    solo_lectura: bool = False
    # Funcionalidades del plan con su nombre (Mi suscripción, CU4 2a).
    funcionalidades: list[FuncionalidadOut] = []


class CredencialesAdmin(BaseModel):
    email: str
    password_temporal: str | None = None  # solo si la generó el sistema


class EmpresaCreada(EmpresaDetalle):
    credenciales: CredencialesAdmin


class EmpresaPublica(BaseModel):
    """Lo mínimo que ve la pantalla de login antes de autenticarse."""
    model_config = ConfigDict(from_attributes=True)
    nombre: str
    slug: str
