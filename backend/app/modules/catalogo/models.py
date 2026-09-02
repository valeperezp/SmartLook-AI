"""Modelo de datos del módulo Catálogo (catálogo maestro + prendas)."""
from sqlalchemy import Boolean, Column, Integer, String, Numeric, ForeignKey
from sqlalchemy.orm import relationship

from app.shared.db.session import Base


class Categoria(Base):
    __tablename__ = "categorias"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(80), unique=True, nullable=False)
    activo = Column(Boolean, default=True)


class Talla(Base):
    __tablename__ = "tallas"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(10), unique=True, nullable=False)
    activo = Column(Boolean, default=True)


class Color(Base):
    __tablename__ = "colores"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(40), unique=True, nullable=False)
    hex = Column(String(7), nullable=True)
    activo = Column(Boolean, default=True)


class Temporada(Base):
    __tablename__ = "temporadas"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(60), unique=True, nullable=False)
    activo = Column(Boolean, default=True)


class Coleccion(Base):
    __tablename__ = "colecciones"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(100), nullable=False)
    temporada_id = Column(Integer, ForeignKey("temporadas.id"), nullable=True)
    activo = Column(Boolean, default=True)

    temporada = relationship("Temporada")


class Producto(Base):
    __tablename__ = "productos"

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(150), nullable=False)
    descripcion = Column(String(500))
    precio = Column(Numeric(10, 2), nullable=False)
    categoria_id = Column(Integer, ForeignKey("categorias.id"), nullable=False)
    temporada_id = Column(Integer, ForeignKey("temporadas.id"), nullable=True)
    coleccion_id = Column(Integer, ForeignKey("colecciones.id"), nullable=True)
    proveedor_id = Column(Integer, ForeignKey("proveedores.id"), nullable=True)
    modelo_ar_url = Column(String(500), nullable=True)
    activo = Column(Boolean, default=True)

    categoria = relationship("Categoria")
    temporada = relationship("Temporada")
    coleccion = relationship("Coleccion")
    proveedor = relationship("Proveedor")
