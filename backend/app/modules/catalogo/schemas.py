"""Esquemas Pydantic (validación de entrada/salida) del módulo Catálogo."""
from pydantic import BaseModel, ConfigDict


# ---------- Categoría ----------
class CategoriaCreate(BaseModel):
    nombre: str


class CategoriaUpdate(BaseModel):
    nombre: str | None = None
    activo: bool | None = None


class CategoriaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    activo: bool


# ---------- Talla ----------
class TallaCreate(BaseModel):
    nombre: str


class TallaUpdate(BaseModel):
    nombre: str | None = None
    activo: bool | None = None


class TallaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    activo: bool


# ---------- Color ----------
class ColorCreate(BaseModel):
    nombre: str
    hex: str | None = None


class ColorUpdate(BaseModel):
    nombre: str | None = None
    hex: str | None = None
    activo: bool | None = None


class ColorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    hex: str | None
    activo: bool


# ---------- Temporada ----------
class TemporadaCreate(BaseModel):
    nombre: str


class TemporadaUpdate(BaseModel):
    nombre: str | None = None
    activo: bool | None = None


class TemporadaOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    activo: bool


# ---------- Colección ----------
class ColeccionCreate(BaseModel):
    nombre: str
    temporada_id: int | None = None


class ColeccionUpdate(BaseModel):
    nombre: str | None = None
    temporada_id: int | None = None
    activo: bool | None = None


class ColeccionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    temporada_id: int | None
    activo: bool
    temporada: TemporadaOut | None = None


# ---------- Producto ----------
class ProductoBase(BaseModel):
    nombre: str
    descripcion: str | None = None
    precio: float
    categoria_id: int
    temporada_id: int | None = None
    coleccion_id: int | None = None
    proveedor_id: int | None = None
    modelo_ar_url: str | None = None


class ProductoCreate(ProductoBase):
    pass


class ProductoUpdate(BaseModel):
    nombre: str | None = None
    descripcion: str | None = None
    precio: float | None = None
    categoria_id: int | None = None
    temporada_id: int | None = None
    coleccion_id: int | None = None
    proveedor_id: int | None = None
    modelo_ar_url: str | None = None
    activo: bool | None = None


class ProductoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    nombre: str
    descripcion: str | None
    precio: float
    categoria_id: int
    temporada_id: int | None
    coleccion_id: int | None
    proveedor_id: int | None
    modelo_ar_url: str | None
    activo: bool
    categoria: CategoriaOut
    temporada: TemporadaOut | None = None
    coleccion: ColeccionOut | None = None
