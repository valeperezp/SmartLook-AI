"""Lógica de negocio del módulo reportes (CU13 — Consultar reportes y dashboards).

Los reportes se calculan sobre reservas/inventario/catálogo (ventas y pagos
todavía no están implementados por el resto del equipo).
"""
from datetime import datetime, timedelta

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Categoria, Producto
from app.modules.inventario import service as inventario_service
from app.modules.inventario.models import Inventario
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.sucursales.models import Sucursal


def reservas_por_estado(db: Session, sucursal_id: int | None = None) -> list[dict]:
    """Cuenta las reservas agrupadas por estado (global o de una sucursal)."""
    query = db.query(Reserva.estado, func.count(Reserva.id))
    if sucursal_id is not None:
        query = query.filter(Reserva.sucursal_id == sucursal_id)
    filas = query.group_by(Reserva.estado).all()
    return [{"estado": estado, "cantidad": cantidad} for estado, cantidad in filas]


def reservas_por_sucursal(db: Session) -> list[dict]:
    """Cuenta reservas y unidades totales agrupadas por sucursal (solo admin, vista global)."""
    filas = (
        db.query(
            Sucursal.id,
            Sucursal.nombre,
            func.count(func.distinct(Reserva.id)),
            func.coalesce(func.sum(ReservaItem.cantidad), 0),
        )
        .outerjoin(Reserva, Reserva.sucursal_id == Sucursal.id)
        .outerjoin(ReservaItem, ReservaItem.reserva_id == Reserva.id)
        .filter(Sucursal.activa.is_(True))
        .group_by(Sucursal.id, Sucursal.nombre)
        .order_by(Sucursal.nombre)
        .all()
    )
    return [
        {
            "sucursal_id": sucursal_id,
            "nombre_sucursal": nombre,
            "cantidad_reservas": cantidad_reservas,
            "total_unidades": int(total_unidades),
        }
        for sucursal_id, nombre, cantidad_reservas, total_unidades in filas
    ]


def productos_mas_reservados(
    db: Session, sucursal_id: int | None = None, limit: int = 10
) -> list[dict]:
    """Ranking de productos por unidades reservadas (excluye reservas canceladas)."""
    query = (
        db.query(
            Producto.id,
            Producto.nombre,
            Categoria.nombre,
            func.coalesce(func.sum(ReservaItem.cantidad), 0),
            func.count(func.distinct(ReservaItem.reserva_id)),
        )
        .join(ReservaItem, ReservaItem.producto_id == Producto.id)
        .join(Reserva, Reserva.id == ReservaItem.reserva_id)
        .outerjoin(Categoria, Categoria.id == Producto.categoria_id)
        .filter(Reserva.estado != "cancelada")
    )
    if sucursal_id is not None:
        query = query.filter(Reserva.sucursal_id == sucursal_id)

    filas = (
        query.group_by(Producto.id, Producto.nombre, Categoria.nombre)
        .order_by(func.coalesce(func.sum(ReservaItem.cantidad), 0).desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "producto_id": producto_id,
            "nombre_producto": nombre,
            "nombre_categoria": nombre_categoria,
            "total_unidades": int(total_unidades),
            "total_reservas": total_reservas,
        }
        for producto_id, nombre, nombre_categoria, total_unidades, total_reservas in filas
    ]


def reservas_por_dia(db: Session, sucursal_id: int | None = None, dias: int = 14) -> list[dict]:
    """Serie temporal de reservas creadas en los últimos N días."""
    desde = datetime.utcnow() - timedelta(days=dias)
    query = db.query(
        func.date(Reserva.creada_en),
        func.count(Reserva.id),
    ).filter(Reserva.creada_en >= desde)
    if sucursal_id is not None:
        query = query.filter(Reserva.sucursal_id == sucursal_id)

    filas = query.group_by(func.date(Reserva.creada_en)).order_by(func.date(Reserva.creada_en)).all()
    return [{"fecha": str(fecha), "cantidad": cantidad} for fecha, cantidad in filas]


def resumen_general(db: Session, sucursal_id: int | None = None) -> dict:
    """Resumen combinado de reservas + inventario para el dashboard de reportes."""
    query_base = db.query(Reserva)
    if sucursal_id is not None:
        query_base = query_base.filter(Reserva.sucursal_id == sucursal_id)
    total_reservas = query_base.count()

    total_unidades_query = db.query(func.coalesce(func.sum(ReservaItem.cantidad), 0)).join(
        Reserva, Reserva.id == ReservaItem.reserva_id
    )
    if sucursal_id is not None:
        total_unidades_query = total_unidades_query.filter(Reserva.sucursal_id == sucursal_id)
    total_unidades = int(total_unidades_query.scalar() or 0)

    por_estado = reservas_por_estado(db, sucursal_id=sucursal_id)

    inv = inventario_service.resumen_global(db, sucursal_id=sucursal_id)

    return {
        "total_reservas": total_reservas,
        "total_unidades_reservadas": total_unidades,
        "reservas_por_estado": por_estado,
        "inventario_disponible": inv["total_disponibles"],
        "inventario_reservado": inv["total_reservados"],
        "productos_stock_bajo": inv["productos_stock_bajo"],
        "productos_agotados": inv["productos_agotados"],
    }
