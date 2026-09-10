"""Lógica de negocio del módulo Inventario (lectura, escritura y movimientos de sucursal)."""
from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Producto
from app.modules.inventario import models, schemas
from app.modules.sucursales.models import Sucursal


def _calcular_estado(inventario: models.Inventario) -> str:
    """Helper para calcular el estado del stock según cantidades."""
    if inventario.cantidad_disponible == 0:
        return "agotado"
    if inventario.cantidad_disponible <= inventario.stock_minimo:
        return "bajo"
    return "disponible"


# =========================================================================
# CONSULTAS / LECTURA
# =========================================================================
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


def obtener_inventario(db: Session, inventario_id: int) -> models.Inventario | None:
    """Obtiene un registro de inventario con sus relaciones cargadas."""
    return (
        db.query(models.Inventario)
        .options(
            joinedload(models.Inventario.producto),
            joinedload(models.Inventario.sucursal),
            joinedload(models.Inventario.talla),
            joinedload(models.Inventario.color),
        )
        .filter(models.Inventario.id == inventario_id, models.Inventario.activo.is_(True))
        .first()
    )


def resumen_global(db: Session, sucursal_id: int | None = None) -> dict:
    """Calcula totales globales o de una sucursal específica."""
    query_base = db.query(models.Inventario).filter(models.Inventario.activo.is_(True))
    if sucursal_id is not None:
        query_base = query_base.filter(models.Inventario.sucursal_id == sucursal_id)

    total_disponibles = (
        query_base.with_entities(func.coalesce(func.sum(models.Inventario.cantidad_disponible), 0)).scalar()
        or 0
    )
    total_reservados = (
        query_base.with_entities(func.coalesce(func.sum(models.Inventario.cantidad_reservada), 0)).scalar()
        or 0
    )
    total_vendidos = (
        query_base.with_entities(func.coalesce(func.sum(models.Inventario.cantidad_vendida), 0)).scalar()
        or 0
    )
    productos_agotados = (
        query_base.filter(models.Inventario.cantidad_disponible == 0)
        .with_entities(func.count(models.Inventario.id))
        .scalar()
        or 0
    )
    productos_stock_bajo = (
        query_base.filter(
            models.Inventario.cantidad_disponible > 0,
            models.Inventario.cantidad_disponible <= models.Inventario.stock_minimo,
        )
        .with_entities(func.count(models.Inventario.id))
        .scalar()
        or 0
    )

    if sucursal_id is not None:
        total_sucursales = 1
    else:
        total_sucursales = db.query(func.count(Sucursal.id)).filter(Sucursal.activa.is_(True)).scalar() or 0

    return {
        "total_disponibles": int(total_disponibles),
        "total_reservados": int(total_reservados),
        "total_vendidos": int(total_vendidos),
        "productos_agotados": int(productos_agotados),
        "productos_stock_bajo": int(productos_stock_bajo),
        "total_sucursales": int(total_sucursales),
    }


def alertas_stock_bajo(db: Session, sucursal_id: int | None = None) -> list[dict]:
    """Devuelve alertas para aquellos registros con existencia menor o igual al stock mínimo."""
    query = (
        db.query(models.Inventario)
        .options(
            joinedload(models.Inventario.producto),
            joinedload(models.Inventario.sucursal),
        )
        .filter(
            models.Inventario.activo.is_(True),
            models.Inventario.cantidad_disponible <= models.Inventario.stock_minimo,
        )
    )

    if sucursal_id is not None:
        query = query.filter(models.Inventario.sucursal_id == sucursal_id)

    items = query.all()

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


# =========================================================================
# GESTIÓN Y MOVIMIENTOS DE INVENTARIO (ESCRITURA - CU15)
# =========================================================================
def crear_o_inicializar_inventario(
    db: Session, data: schemas.InventarioCreate, usuario_id: int | None = None
) -> models.Inventario:
    """Crea un nuevo registro de inventario o inicializa stock si aún no existía."""
    existente = (
        db.query(models.Inventario)
        .filter(
            models.Inventario.producto_id == data.producto_id,
            models.Inventario.sucursal_id == data.sucursal_id,
            models.Inventario.talla_id == data.talla_id,
            models.Inventario.color_id == data.color_id,
        )
        .first()
    )
    if existente:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ya existe un registro de inventario para este producto, talla y color en esta sucursal.",
        )

    nuevo_inv = models.Inventario(
        producto_id=data.producto_id,
        sucursal_id=data.sucursal_id,
        talla_id=data.talla_id,
        color_id=data.color_id,
        cantidad_disponible=data.cantidad_inicial,
        stock_minimo=data.stock_minimo,
        activo=True,
    )
    db.add(nuevo_inv)
    db.commit()
    db.refresh(nuevo_inv)

    if data.cantidad_inicial > 0:
        mov = models.MovimientoInventario(
            inventario_id=nuevo_inv.id,
            tipo="entrada",
            cantidad=data.cantidad_inicial,
            motivo="Carga inicial de inventario en sucursal",
            usuario_id=usuario_id,
        )
        db.add(mov)
        db.commit()

    return obtener_inventario(db, nuevo_inv.id)


def registrar_movimiento(
    db: Session, data: schemas.MovimientoCreate, usuario_id: int | None = None
) -> models.MovimientoInventario:
    """Registra una entrada o salida de inventario y actualiza la cantidad disponible."""
    inv = db.query(models.Inventario).filter(models.Inventario.id == data.inventario_id).first()
    if not inv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Registro de inventario no encontrado")

    if data.tipo == "entrada":
        inv.cantidad_disponible += data.cantidad
    elif data.tipo == "salida":
        if inv.cantidad_disponible < data.cantidad:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Stock insuficiente: disponibles {inv.cantidad_disponible}, se intenta retirar {data.cantidad}.",
            )
        inv.cantidad_disponible -= data.cantidad
    else:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Tipo de movimiento no válido: {data.tipo}")

    mov = models.MovimientoInventario(
        inventario_id=inv.id,
        tipo=data.tipo,
        cantidad=data.cantidad,
        motivo=data.motivo,
        usuario_id=usuario_id,
    )
    db.add(mov)
    db.commit()
    return (
        db.query(models.MovimientoInventario)
        .options(
            joinedload(models.MovimientoInventario.inventario).joinedload(models.Inventario.producto),
            joinedload(models.MovimientoInventario.inventario).joinedload(models.Inventario.sucursal),
            joinedload(models.MovimientoInventario.usuario),
        )
        .filter(models.MovimientoInventario.id == mov.id)
        .first()
    )


def ajustar_stock(
    db: Session, data: schemas.AjusteStockCreate, usuario_id: int | None = None
) -> models.Inventario:
    """Ajusta la cantidad disponible a un conteo físico real y genera un movimiento de tipo 'ajuste'."""
    inv = db.query(models.Inventario).filter(models.Inventario.id == data.inventario_id).first()
    if not inv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Registro de inventario no encontrado")

    diferencia = data.nueva_cantidad - inv.cantidad_disponible
    inv.cantidad_disponible = data.nueva_cantidad

    mov = models.MovimientoInventario(
        inventario_id=inv.id,
        tipo="ajuste",
        cantidad=diferencia,
        motivo=data.motivo,
        usuario_id=usuario_id,
    )
    db.add(mov)
    db.commit()
    return obtener_inventario(db, inv.id)


def actualizar_stock_minimo(
    db: Session, inventario_id: int, data: schemas.StockMinimoUpdate
) -> models.Inventario:
    """Actualiza el umbral de stock mínimo para un registro de inventario."""
    inv = db.query(models.Inventario).filter(models.Inventario.id == inventario_id).first()
    if not inv:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Registro de inventario no encontrado")

    inv.stock_minimo = data.stock_minimo
    db.commit()
    return obtener_inventario(db, inv.id)


def listar_movimientos(
    db: Session,
    sucursal_id: int | None = None,
    inventario_id: int | None = None,
    tipo: str | None = None,
    limit: int = 100,
) -> list[models.MovimientoInventario]:
    """Lista el historial de movimientos de inventario con filtros."""
    query = (
        db.query(models.MovimientoInventario)
        .join(models.MovimientoInventario.inventario)
        .options(
            joinedload(models.MovimientoInventario.inventario).joinedload(models.Inventario.producto),
            joinedload(models.MovimientoInventario.inventario).joinedload(models.Inventario.sucursal),
            joinedload(models.MovimientoInventario.usuario),
        )
    )

    if inventario_id is not None:
        query = query.filter(models.MovimientoInventario.inventario_id == inventario_id)
    if sucursal_id is not None:
        query = query.filter(models.Inventario.sucursal_id == sucursal_id)
    if tipo is not None:
        query = query.filter(models.MovimientoInventario.tipo == tipo)

    return query.order_by(models.MovimientoInventario.creado_en.desc()).limit(limit).all()
