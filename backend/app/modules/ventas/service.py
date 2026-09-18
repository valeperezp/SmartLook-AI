"""Lógica de negocio del módulo Ventas (CU17 - Venta presencial)."""
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Producto
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.sucursales.models import Sucursal
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


def crear_venta_online(db: Session, data: schemas.VentaOnlineCreate, cliente_id: int) -> models.Venta:
    """Crea una venta online en estado pendiente sin descontar inventario."""
    # 1. Validar que la sucursal exista
    sucursal = db.query(Sucursal).filter(Sucursal.id == data.sucursal_id).first()
    if not sucursal:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")

    # 2. Crear cabecera de la venta
    venta = models.Venta(
        cliente_id=cliente_id,
        sucursal_id=data.sucursal_id,
        cajero_id=None,
        canal="online",
        estado="pendiente",
        total=0,
    )
    db.add(venta)
    db.flush()

    total = 0.0

    # 3. Crear items con precio unitario obtenido de BD
    for item_data in data.items:
        producto = db.query(Producto).filter(Producto.id == item_data.producto_id).first()
        if not producto:
            raise HTTPException(status_code=404, detail=f"Producto {item_data.producto_id} no encontrado")

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

    venta.total = total
    db.commit()
    db.refresh(venta)

    return _obtener_venta_con_relaciones(db, venta.id)


def completar_venta_y_descontar_stock(db: Session, venta_id: int) -> models.Venta:
    """Confirma una venta online pendiente, descuenta stock y registra movimientos de inventario."""
    venta = _obtener_venta_con_relaciones(db, venta_id)
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    if venta.estado != "pendiente":
        raise HTTPException(
            status_code=400,
            detail=f"La venta no está pendiente (estado actual: {venta.estado})",
        )

    # 1. Verificar disponibilidad de stock para todos los items antes de modificar
    inventarios_a_descontar = []
    for item in venta.items:
        inventario = _buscar_inventario(
            db, item.producto_id, venta.sucursal_id, item.talla_id, item.color_id
        )
        if not inventario or inventario.cantidad_disponible < item.cantidad:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Stock insuficiente al confirmar pago",
            )
        inventarios_a_descontar.append((inventario, item))

    # 2. Descontar stock y registrar movimientos de auditoría
    for inventario, item in inventarios_a_descontar:
        inventario.cantidad_disponible -= item.cantidad
        inventario.cantidad_vendida += item.cantidad

        mov = MovimientoInventario(
            inventario_id=inventario.id,
            tipo="venta",
            cantidad=item.cantidad,
            motivo=f"Venta online #{venta.id}",
            usuario_id=venta.cliente_id,
        )
        db.add(mov)

    # 3. Marcar venta como completada
    venta.estado = "completada"
    db.commit()
    db.refresh(venta)

    return _obtener_venta_con_relaciones(db, venta.id)


def listar_mis_compras(db: Session, cliente_id: int) -> list[models.Venta]:
    """Lista las compras online del cliente autenticado."""
    return (
        db.query(models.Venta)
        .options(
            joinedload(models.Venta.items).joinedload(models.VentaItem.producto),
            joinedload(models.Venta.items).joinedload(models.VentaItem.talla),
            joinedload(models.Venta.items).joinedload(models.VentaItem.color),
            joinedload(models.Venta.sucursal),
        )
        .filter(models.Venta.cliente_id == cliente_id, models.Venta.canal == "online")
        .order_by(models.Venta.creada_en.desc())
        .all()
    )
