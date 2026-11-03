"""Esquemas Pydantic del módulo Empresas (empresas, planes y suscripciones)."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

EstadoSuscripcion = Literal["activa", "suspendida", "cancelada", "reemplazada"]


# ---------- Planes (CU3) ----------

class PlanBase(BaseModel):
    nombre: str = Field(min_length=2, max_length=60)
    descripcion: str | None = None
    precio_mensual: Decimal = Field(ge=0)
    max_sucursales: int | None = Field(default=None, ge=1)
    max_usuarios: int | None = Field(default=None, ge=1)
    max_productos: int | None = Field(default=None, ge=1)
    incluye_ia: bool = False


class PlanCreate(PlanBase):
    pass


class PlanUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=60)
    descripcion: str | None = None
    precio_mensual: Decimal | None = Field(default=None, ge=0)
    max_sucursales: int | None = Field(default=None, ge=1)
    max_usuarios: int | None = Field(default=None, ge=1)
    max_productos: int | None = Field(default=None, ge=1)
    incluye_ia: bool | None = None
    activo: bool | None = None


class PlanOut(PlanBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    activo: bool


# ---------- Suscripciones (CU4) ----------

class SuscripcionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    empresa_id: int
    plan_id: int
    estado: str
    fecha_inicio: date
    fecha_fin: date | None = None
    creado_en: datetime | None = None
    plan: PlanOut


class SuscripcionAsignar(BaseModel):
    """Asigna o cambia el plan de una empresa. Reemplaza a la suscripción vigente."""
    plan_id: int
    fecha_fin: date | None = None


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
    nombre: str = Field(min_length=2, max_length=150)
    nit: str | None = None
    email: str | None = None
    telefono: str | None = None
    direccion: str | None = None
    logo_url: str | None = Field(default=None, max_length=500)


class AdminInicial(BaseModel):
    nombre: str
    email: str
    password: str = Field(min_length=6)


class EmpresaCreate(EmpresaBase):
    slug: str = Field(min_length=2, max_length=60, pattern=r"^[a-z0-9]+(-[a-z0-9]+)*$")
    plan_id: int
    fecha_fin: date | None = None
    administrador: AdminInicial


class EmpresaUpdate(BaseModel):
    nombre: str | None = Field(default=None, min_length=2, max_length=150)
    nit: str | None = None
    email: str | None = None
    telefono: str | None = None
    direccion: str | None = None
    logo_url: str | None = Field(default=None, max_length=500)
    activa: bool | None = None


class EmpresaOut(EmpresaBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    slug: str
    activa: bool
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


class EmpresaPublica(BaseModel):
    """Lo mínimo que ve la pantalla de login antes de autenticarse."""
    model_config = ConfigDict(from_attributes=True)
    nombre: str
    slug: str
