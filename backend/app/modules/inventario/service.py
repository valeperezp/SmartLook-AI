"""Lógica de negocio del módulo Inventario (solo lectura)."""
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Producto
from app.modules.inventario import models
from app.modules.sucursales.models import Sucursal


def _calcular_estado(inventario: models.Inventario) -> str:
    """Helper para calcular el estado del stock según cantidades."""
    if inventario.cantidad_disponible == 0:
        return "agotado"
    if inventario.cantidad_disponible <= inventario.stock_minimo:
        return "bajo"
    return "disponible"


def listar_inventario(
    db: Session,
    sucursal_id: int | None = None,
    producto_id: int | None = None,
    categoria_id: int | None = None,
    talla_id: int | None = None,
    color_id: int | None = None,
    solo_disponibles: bool = False,
    solo_agotados: bool = False,
) -> list[models.Inventario]:
    """Lista inventario con joins a Producto, Sucursal, Talla y Color, ordenado por producto."""
    query = (
        db.query(models.Inventario)
        .join(models.Inventario.producto)
        .options(
            joinedload(models.Inventario.producto),
            joinedload(models.Inventario.sucursal),
            joinedload(models.Inventario.talla),
            joinedload(models.Inventario.color),
        )
        .filter(models.Inventario.activo.is_(True))
    )

    if sucursal_id is not None:
        query = query.filter(models.Inventario.sucursal_id == sucursal_id)
    if producto_id is not None:
        query = query.filter(models.Inventario.producto_id == producto_id)
    if categoria_id is not None:
        query = query.filter(Producto.categoria_id == categoria_id)
    if talla_id is not None:
        query = query.filter(models.Inventario.talla_id == talla_id)
    if color_id is not None:
        query = query.filter(models.Inventario.color_id == color_id)
    if solo_disponibles:
        query = query.filter(models.Inventario.cantidad_disponible > 0)
    if solo_agotados:
        query = query.filter(models.Inventario.cantidad_disponible == 0)

    return query.order_by(Producto.nombre, models.Inventario.id).all()


def inventario_por_sucursal(db: Session, sucursal_id: int) -> list[models.Inventario]:
    """Obtiene el inventario filtrado por sucursal."""
    return listar_inventario(db, sucursal_id=sucursal_id)


def inventario_por_producto(db: Session, producto_id: int) -> list[models.Inventario]:
    """Obtiene la distribución del inventario de un producto en todas las sucursales."""
    return listar_inventario(db, producto_id=producto_id)


def resumen_global(db: Session) -> dict:
    """Calcula totales globales de existencias, reservas, ventas y alertas."""
    total_disponibles = (
        db.query(func.coalesce(func.sum(models.Inventario.cantidad_disponible), 0))
        .filter(models.Inventario.activo.is_(True))
        .scalar()
        or 0
    )
    total_reservados = (
        db.query(func.coalesce(func.sum(models.Inventario.cantidad_reservada), 0))
        .filter(models.Inventario.activo.is_(True))
        .scalar()
        or 0
    )
    total_vendidos = (
        db.query(func.coalesce(func.sum(models.Inventario.cantidad_vendida), 0))
        .filter(models.Inventario.activo.is_(True))
        .scalar()
        or 0
    )
    productos_agotados = (
        db.query(func.count(models.Inventario.id))
        .filter(
            models.Inventario.activo.is_(True),
            models.Inventario.cantidad_disponible == 0,
        )
        .scalar()
        or 0
    )
    productos_stock_bajo = (
        db.query(func.count(models.Inventario.id))
        .filter(
            models.Inventario.activo.is_(True),
            models.Inventario.cantidad_disponible > 0,
            models.Inventario.cantidad_disponible <= models.Inventario.stock_minimo,
        )
        .scalar()
        or 0
    )
    total_sucursales = (
        db.query(func.count(Sucursal.id))
        .filter(Sucursal.activa.is_(True))
        .scalar()
        or 0
    )

    return {
        "total_disponibles": int(total_disponibles),
        "total_reservados": int(total_reservados),
        "total_vendidos": int(total_vendidos),
        "productos_agotados": int(productos_agotados),
        "productos_stock_bajo": int(productos_stock_bajo),
        "total_sucursales": int(total_sucursales),
    }


def alertas_stock_bajo(db: Session) -> list[dict]:
    """Devuelve alertas para aquellos registros con existencia menor o igual al stock mínimo."""
    items = (
        db.query(models.Inventario)
        .options(
            joinedload(models.Inventario.producto),
            joinedload(models.Inventario.sucursal),
        )
        .filter(
            models.Inventario.activo.is_(True),
            models.Inventario.cantidad_disponible <= models.Inventario.stock_minimo,
        )
        .all()
    )

    alertas = []
    for item in items:
        if item.cantidad_disponible == 0:
            mensaje = f"Producto agotado en {item.nombre_sucursal}"
        else:
            mensaje = (
                f"Stock bajo en {item.nombre_sucursal}: quedan {item.cantidad_disponible} "
                f"unidad(es) (mínimo: {item.stock_minimo})"
            )
        alertas.append({
            "inventario_id": item.id,
            "nombre_producto": item.nombre_producto,
            "nombre_sucursal": item.nombre_sucursal,
            "cantidad_disponible": item.cantidad_disponible,
            "stock_minimo": item.stock_minimo,
            "mensaje": mensaje,
        })

    return alertas
