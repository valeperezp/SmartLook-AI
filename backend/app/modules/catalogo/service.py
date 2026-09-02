"""Lógica de negocio del módulo Catálogo (independiente de FastAPI/HTTP)."""
from sqlalchemy.orm import Session

from app.modules.catalogo import models, schemas


def _aplicar_update(instancia, data) -> None:
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(instancia, campo, valor)


# ---------- Categoría ----------
def listar_categorias(db: Session) -> list[models.Categoria]:
    return db.query(models.Categoria).order_by(models.Categoria.nombre).all()


def obtener_categoria(db: Session, categoria_id: int) -> models.Categoria | None:
    return db.query(models.Categoria).filter(models.Categoria.id == categoria_id).first()


def crear_categoria(db: Session, data: schemas.CategoriaCreate) -> models.Categoria:
    categoria = models.Categoria(**data.model_dump())
    db.add(categoria)
    db.commit()
    db.refresh(categoria)
    return categoria


def actualizar_categoria(db: Session, categoria_id: int, data: schemas.CategoriaUpdate) -> models.Categoria | None:
    categoria = obtener_categoria(db, categoria_id)
    if not categoria:
        return None
    _aplicar_update(categoria, data)
    db.commit()
    db.refresh(categoria)
    return categoria


def eliminar_categoria(db: Session, categoria_id: int) -> models.Categoria | None:
    categoria = obtener_categoria(db, categoria_id)
    if not categoria:
        return None
    categoria.activo = False
    db.commit()
    db.refresh(categoria)
    return categoria


# ---------- Talla ----------
def listar_tallas(db: Session) -> list[models.Talla]:
    return db.query(models.Talla).order_by(models.Talla.id).all()


def obtener_talla(db: Session, talla_id: int) -> models.Talla | None:
    return db.query(models.Talla).filter(models.Talla.id == talla_id).first()


def crear_talla(db: Session, data: schemas.TallaCreate) -> models.Talla:
    talla = models.Talla(**data.model_dump())
    db.add(talla)
    db.commit()
    db.refresh(talla)
    return talla


def actualizar_talla(db: Session, talla_id: int, data: schemas.TallaUpdate) -> models.Talla | None:
    talla = obtener_talla(db, talla_id)
    if not talla:
        return None
    _aplicar_update(talla, data)
    db.commit()
    db.refresh(talla)
    return talla


def eliminar_talla(db: Session, talla_id: int) -> models.Talla | None:
    talla = obtener_talla(db, talla_id)
    if not talla:
        return None
    talla.activo = False
    db.commit()
    db.refresh(talla)
    return talla


# ---------- Color ----------
def listar_colores(db: Session) -> list[models.Color]:
    return db.query(models.Color).order_by(models.Color.id).all()


def obtener_color(db: Session, color_id: int) -> models.Color | None:
    return db.query(models.Color).filter(models.Color.id == color_id).first()


def crear_color(db: Session, data: schemas.ColorCreate) -> models.Color:
    color = models.Color(**data.model_dump())
    db.add(color)
    db.commit()
    db.refresh(color)
    return color


def actualizar_color(db: Session, color_id: int, data: schemas.ColorUpdate) -> models.Color | None:
    color = obtener_color(db, color_id)
    if not color:
        return None
    _aplicar_update(color, data)
    db.commit()
    db.refresh(color)
    return color


def eliminar_color(db: Session, color_id: int) -> models.Color | None:
    color = obtener_color(db, color_id)
    if not color:
        return None
    color.activo = False
    db.commit()
    db.refresh(color)
    return color


# ---------- Temporada ----------
def listar_temporadas(db: Session) -> list[models.Temporada]:
    return db.query(models.Temporada).order_by(models.Temporada.id).all()


def obtener_temporada(db: Session, temporada_id: int) -> models.Temporada | None:
    return db.query(models.Temporada).filter(models.Temporada.id == temporada_id).first()


def crear_temporada(db: Session, data: schemas.TemporadaCreate) -> models.Temporada:
    temporada = models.Temporada(**data.model_dump())
    db.add(temporada)
    db.commit()
    db.refresh(temporada)
    return temporada


def actualizar_temporada(db: Session, temporada_id: int, data: schemas.TemporadaUpdate) -> models.Temporada | None:
    temporada = obtener_temporada(db, temporada_id)
    if not temporada:
        return None
    _aplicar_update(temporada, data)
    db.commit()
    db.refresh(temporada)
    return temporada


def eliminar_temporada(db: Session, temporada_id: int) -> models.Temporada | None:
    temporada = obtener_temporada(db, temporada_id)
    if not temporada:
        return None
    temporada.activo = False
    db.commit()
    db.refresh(temporada)
    return temporada


# ---------- Colección ----------
def listar_colecciones(db: Session) -> list[models.Coleccion]:
    return db.query(models.Coleccion).order_by(models.Coleccion.id).all()


def obtener_coleccion(db: Session, coleccion_id: int) -> models.Coleccion | None:
    return db.query(models.Coleccion).filter(models.Coleccion.id == coleccion_id).first()


def crear_coleccion(db: Session, data: schemas.ColeccionCreate) -> models.Coleccion:
    coleccion = models.Coleccion(**data.model_dump())
    db.add(coleccion)
    db.commit()
    db.refresh(coleccion)
    return coleccion


def actualizar_coleccion(db: Session, coleccion_id: int, data: schemas.ColeccionUpdate) -> models.Coleccion | None:
    coleccion = obtener_coleccion(db, coleccion_id)
    if not coleccion:
        return None
    _aplicar_update(coleccion, data)
    db.commit()
    db.refresh(coleccion)
    return coleccion


def eliminar_coleccion(db: Session, coleccion_id: int) -> models.Coleccion | None:
    coleccion = obtener_coleccion(db, coleccion_id)
    if not coleccion:
        return None
    coleccion.activo = False
    db.commit()
    db.refresh(coleccion)
    return coleccion


# ---------- Producto ----------
def listar_productos(
    db: Session, categoria_id: int | None = None, incluir_inactivos: bool = False
) -> list[models.Producto]:
    query = db.query(models.Producto)
    if not incluir_inactivos:
        query = query.filter(models.Producto.activo.is_(True))
    if categoria_id:
        query = query.filter(models.Producto.categoria_id == categoria_id)
    return query.all()


def obtener_producto(db: Session, producto_id: int) -> models.Producto | None:
    return db.query(models.Producto).filter(models.Producto.id == producto_id).first()


def crear_producto(db: Session, data: schemas.ProductoCreate) -> models.Producto:
    producto = models.Producto(**data.model_dump())
    db.add(producto)
    db.commit()
    db.refresh(producto)
    return producto


def actualizar_producto(db: Session, producto_id: int, data: schemas.ProductoUpdate) -> models.Producto | None:
    producto = obtener_producto(db, producto_id)
    if not producto:
        return None
    _aplicar_update(producto, data)
    db.commit()
    db.refresh(producto)
    return producto


def eliminar_producto(db: Session, producto_id: int) -> models.Producto | None:
    producto = obtener_producto(db, producto_id)
    if not producto:
        return None
    producto.activo = False
    db.commit()
    db.refresh(producto)
    return producto
