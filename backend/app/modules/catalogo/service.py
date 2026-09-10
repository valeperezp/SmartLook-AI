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


def _calcular_estado_disponibilidad(total: int, stock_minimo: int = 5) -> str:
    """Calcula el estado agregado según cantidad total."""
    if total == 0:
        return "agotado"
    if total <= stock_minimo:
        return "bajo"
    return "disponible"


def obtener_disponibilidad_producto(db: Session, producto_id: int) -> dict | None:
    """
    Devuelve la disponibilidad de un producto agrupada por sucursal,
    con desglose por talla y color.
    """
    from app.modules.inventario.models import Inventario
    from app.modules.sucursales.models import Sucursal

    producto = obtener_producto(db, producto_id)
    if not producto:
        return None

    # Obtener todas las sucursales activas
    sucursales = db.query(Sucursal).filter(Sucursal.activa.is_(True)).order_by(Sucursal.id).all()

    disponibilidad = []
    total_global = 0
    sucursales_con_stock = 0

    for suc in sucursales:
        # Obtener items de inventario de este producto en esta sucursal
        items = (
            db.query(Inventario)
            .filter(
                Inventario.producto_id == producto_id,
                Inventario.sucursal_id == suc.id,
                Inventario.activo.is_(True),
            )
            .all()
        )

        total_sucursal = sum(item.cantidad_disponible for item in items)
        total_global += total_sucursal
        if total_sucursal > 0:
            sucursales_con_stock += 1

        disponibilidad.append({
            "sucursal_id": suc.id,
            "nombre_sucursal": suc.nombre,
            "ciudad": getattr(suc, "ciudad", None),
            "total_disponible": total_sucursal,
            "estado": _calcular_estado_disponibilidad(total_sucursal),
            "items": [
                {
                    "talla_id": item.talla_id,
                    "nombre_talla": item.nombre_talla,
                    "color_id": item.color_id,
                    "nombre_color": item.nombre_color,
                    "cantidad_disponible": item.cantidad_disponible,
                }
                for item in items
            ],
        })

    return {
        "producto_id": producto.id,
        "nombre_producto": producto.nombre,
        "precio": float(producto.precio),
        "imagen_url": None,
        "total_global": total_global,
        "sucursales_con_stock": sucursales_con_stock,
        "disponibilidad": disponibilidad,
    }


def listar_productos_con_disponibilidad(
    db: Session,
    categoria_id: int | None = None,
    sucursal_id: int | None = None,
) -> list[dict]:
    """
    Lista productos con su resumen de disponibilidad agregado.
    Si sucursal_id se especifica, solo devuelve productos con stock en esa sucursal.
    """
    from app.modules.inventario.models import Inventario

    productos = listar_productos(db, categoria_id=categoria_id)
    resultados = []

    for prod in productos:
        query = (
            db.query(Inventario)
            .filter(
                Inventario.producto_id == prod.id,
                Inventario.activo.is_(True),
            )
        )
        if sucursal_id is not None:
            query = query.filter(Inventario.sucursal_id == sucursal_id)

        items = query.all()
        total_disponible = sum(item.cantidad_disponible for item in items)
        sucursales_ids = set(item.sucursal_id for item in items if item.cantidad_disponible > 0)

        resultados.append({
            "producto": prod,
            "total_disponible": total_disponible,
            "sucursales_con_stock": len(sucursales_ids),
            "estado_global": _calcular_estado_disponibilidad(total_disponible),
        })

    return resultados

