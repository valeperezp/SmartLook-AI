"""Lógica de negocio del módulo Ventas (CU17 - Venta presencial)."""
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Producto
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.ventas import models, schemas


def _buscar_inventario(db: Session, producto_id: int, sucursal_id: int, talla_id: int | None, color_id: int | None) -> Inventario | None:
    query = db.query(Inventario).filter(
        Inventario.producto_id == producto_id,
        Inventario.sucursal_id == sucursal_id,
        Inventario.activo.is_(True),
    )
    if talla_id is not None:
        query = query.filter(Inventario.talla_id == talla_id)
    if color_id is not None:
        query = query.filter(Inventario.color_id == color_id)
    return query.first()


def crear_venta_presencial(db: Session, data: schemas.VentaPresencialCreate, cajero_id: int) -> models.Venta:
    """Crea una venta presencial atómica: crea venta + items + descuenta stock + registra movimientos."""
    # 1. Crear la venta
    venta = models.Venta(
        cliente_id=data.cliente_id,
        sucursal_id=data.sucursal_id,
        cajero_id=cajero_id,
        canal="presencial",
        estado="completada",
        total=0,
    )
    db.add(venta)
    db.flush()

    total = 0.0

    # 2. Procesar cada item
    for item_data in data.items:
        producto = db.query(Producto).filter(Producto.id == item_data.producto_id).first()
        if not producto:
            raise HTTPException(status_code=404, detail=f"Producto {item_data.producto_id} no encontrado")

        inventario = _buscar_inventario(db, item_data.producto_id, data.sucursal_id, item_data.talla_id, item_data.color_id)
        if not inventario:
            raise HTTPException(status_code=404, detail=f"No hay inventario para '{producto.nombre}' en esta sucursal con la talla/color seleccionados")

        if inventario.cantidad_disponible < item_data.cantidad:
            raise HTTPException(
                status_code=400,
                detail=f"Stock insuficiente para '{producto.nombre}'. Disponible: {inventario.cantidad_disponible}, solicitado: {item_data.cantidad}",
            )

        # Descontar stock
        inventario.cantidad_disponible -= item_data.cantidad
        inventario.cantidad_vendida += item_data.cantidad

        # Crear item
        precio = float(producto.precio)
        item = models.VentaItem(
            venta_id=venta.id,
            producto_id=item_data.producto_id,
            talla_id=item_data.talla_id,
            color_id=item_data.color_id,
            cantidad=item_data.cantidad,
            precio_unitario=precio,
        )
        db.add(item)
        total += precio * item_data.cantidad

        # Registrar movimiento de inventario
        mov = MovimientoInventario(
            inventario_id=inventario.id,
            tipo="venta",
            cantidad=item_data.cantidad,
            motivo=f"Venta presencial",
            usuario_id=cajero_id,
        )
        db.add(mov)

    # 3. Actualizar total
    venta.total = total
    db.commit()
    db.refresh(venta)

    return _obtener_venta_con_relaciones(db, venta.id)


def _obtener_venta_con_relaciones(db: Session, venta_id: int) -> models.Venta | None:
    return (
        db.query(models.Venta)
        .options(
            joinedload(models.Venta.items).joinedload(models.VentaItem.producto),
            joinedload(models.Venta.items).joinedload(models.VentaItem.talla),
            joinedload(models.Venta.items).joinedload(models.VentaItem.color),
            joinedload(models.Venta.sucursal),
            joinedload(models.Venta.cajero),
            joinedload(models.Venta.cliente),
        )
        .filter(models.Venta.id == venta_id)
        .first()
    )


def obtener_venta(db: Session, venta_id: int) -> models.Venta | None:
    return _obtener_venta_con_relaciones(db, venta_id)


def listar_ventas_por_sucursal(db: Session, sucursal_id: int) -> list[models.Venta]:
    return (
        db.query(models.Venta)
        .options(
            joinedload(models.Venta.items).joinedload(models.VentaItem.producto),
            joinedload(models.Venta.sucursal),
            joinedload(models.Venta.cajero),
            joinedload(models.Venta.cliente),
        )
        .filter(models.Venta.sucursal_id == sucursal_id)
        .order_by(models.Venta.creada_en.desc())
        .all()
    )


def listar_todas_ventas(db: Session) -> list[models.Venta]:
    return (
        db.query(models.Venta)
        .options(
            joinedload(models.Venta.sucursal),
            joinedload(models.Venta.cajero),
            joinedload(models.Venta.cliente),
        )
        .order_by(models.Venta.creada_en.desc())
        .all()
    )
