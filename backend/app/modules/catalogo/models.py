"""Modelo de datos del módulo Catálogo (catálogo maestro + prendas).

Cada empresa arma su propio catálogo maestro (CU7): los nombres son únicos
dentro de la empresa, no en toda la plataforma.
"""
from sqlalchemy import Boolean, Column, Integer, String, Numeric, ForeignKey, UniqueConstraint
from sqlalchemy.orm import relationship

from app.shared.db.session import Base


def _empresa_id():
    return Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)


class Categoria(Base):
    __tablename__ = "categorias"
    __table_args__ = (UniqueConstraint("empresa_id", "nombre", name="uq_categorias_empresa_nombre"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(80), nullable=False)
    activo = Column(Boolean, default=True)


class Talla(Base):
    __tablename__ = "tallas"
    __table_args__ = (UniqueConstraint("empresa_id", "nombre", name="uq_tallas_empresa_nombre"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(10), nullable=False)
    activo = Column(Boolean, default=True)


class Color(Base):
    __tablename__ = "colores"
    __table_args__ = (UniqueConstraint("empresa_id", "nombre", name="uq_colores_empresa_nombre"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(40), nullable=False)
    hex = Column(String(7), nullable=True)
    activo = Column(Boolean, default=True)


class Temporada(Base):
    __tablename__ = "temporadas"
    __table_args__ = (UniqueConstraint("empresa_id", "nombre", name="uq_temporadas_empresa_nombre"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(60), nullable=False)
    activo = Column(Boolean, default=True)


class Coleccion(Base):
    __tablename__ = "colecciones"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(100), nullable=False)
    temporada_id = Column(Integer, ForeignKey("temporadas.id"), nullable=True)
    activo = Column(Boolean, default=True)

    temporada = relationship("Temporada")


class Producto(Base):
    __tablename__ = "productos"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = _empresa_id()
    nombre = Column(String(150), nullable=False)
    descripcion = Column(String(500))
    precio = Column(Numeric(10, 2), nullable=False)
    categoria_id = Column(Integer, ForeignKey("categorias.id"), nullable=False)
    temporada_id = Column(Integer, ForeignKey("temporadas.id"), nullable=True)
    coleccion_id = Column(Integer, ForeignKey("colecciones.id"), nullable=True)
    proveedor_id = Column(Integer, ForeignKey("proveedores.id"), nullable=True)
    modelo_ar_url = Column(String(500), nullable=True)
    imagen_url = Column(String(500), nullable=True)
    activo = Column(Boolean, default=True)

    categoria = relationship("Categoria")
    temporada = relationship("Temporada")
    coleccion = relationship("Coleccion")
    proveedor = relationship("Proveedor")
    variantes = relationship(
        "VarianteProducto", back_populates="producto", order_by="VarianteProducto.id",
        cascade="all, delete-orphan",
    )


class VarianteProducto(Base):
    """Variante de un producto (CU7): combinación de talla y color con su precio.

    El inventario de cada sucursal se lleva por producto + talla + color; la variante existe
    aunque una sucursal todavía no la tenga cargada (CU7 8a).
    """
    __tablename__ = "producto_variantes"
    __table_args__ = (
        UniqueConstraint("producto_id", "talla_id", "color_id", name="uq_producto_variantes_talla_color"),
    )

    id = Column(Integer, primary_key=True, index=True)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False, index=True)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    sku = Column(String(60), nullable=True)
    precio = Column(Numeric(10, 2), nullable=True)  # NULL = el precio del producto
    activo = Column(Boolean, default=True, nullable=False)

    producto = relationship("Producto", back_populates="variantes")
    talla = relationship("Talla")
    color = relationship("Color")

    @property
    def nombre_talla(self) -> str | None:
        return self.talla.nombre if self.talla else None

    @property
    def nombre_color(self) -> str | None:
        return self.color.nombre if self.color else None

    @property
    def precio_efectivo(self) -> float:
        return float(self.precio if self.precio is not None else self.producto.precio)
