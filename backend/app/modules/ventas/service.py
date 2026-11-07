"""Lógica de negocio del módulo Ventas (CU17 - Venta presencial)."""
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Color, Producto, Talla
from app.modules.fidelizacion import service as fidelizacion
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
    return query.with_for_update().populate_existing().first()


def _empresa_de_sucursal(db: Session, sucursal_id: int) -> int:
    sucursal = db.get(Sucursal, sucursal_id)
    if sucursal is None:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")
    return sucursal.empresa_id


def nombre_variante(db: Session, producto: Producto, talla_id: int | None, color_id: int | None) -> str:
    """'Camisa Talla M Negro': así se nombra una variante en los mensajes de conflicto de stock."""
    nombre = producto.nombre
    if talla_id is not None:
        talla = db.get(Talla, talla_id)
        if talla:
            nombre += f" Talla {talla.nombre}"
    if color_id is not None:
        color = db.get(Color, color_id)
        if color:
            nombre += f" {color.nombre}"
    return nombre


def agrupar_por_variante(items) -> dict[tuple, int]:
    """Suma las cantidades de las líneas que repiten (producto, talla, color)."""
    pedido: dict[tuple, int] = {}
    for it in items:
        clave = (it.producto_id, it.talla_id, it.color_id)
        pedido[clave] = pedido.get(clave, 0) + it.cantidad
    return pedido


def detectar_faltantes_de_stock(db: Session, sucursal_id: int, items) -> list[str]:
    """Qué de lo pedido no se puede entregar con el stock actual de la sucursal (lista vacía = todo alcanza).

    No toca nada. Un producto inexistente no se reporta aquí (lo hace `crear_venta_presencial` con su 404).
    """
    faltantes: list[str] = []
    for (producto_id, talla_id, color_id), cantidad in agrupar_por_variante(items).items():
        producto = db.get(Producto, producto_id)
        if producto is None:
            continue
        nombre = nombre_variante(db, producto, talla_id, color_id)
        inventario = _buscar_inventario(db, producto_id, sucursal_id, talla_id, color_id)
        if inventario is None:
            faltantes.append(f"No hay inventario de {nombre} en esta sucursal")
        elif inventario.cantidad_disponible < cantidad:
            faltantes.append(f"Stock insuficiente en {nombre}. Disponible: {inventario.cantidad_disponible}, solicitado: {cantidad}")
    return faltantes


def crear_venta_en_conflicto(db: Session, data: schemas.VentaPresencialCreate, cajero_id: int) -> models.Venta:
    """Guarda una venta hecha offline que el servidor no pudo cumplir por falta de stock (CU13).

    Queda con estado `en_conflicto` y sus ítems, pero NO descuenta stock ni registra movimientos: un encargado la
    resuelve después (anular, ajustar la variante o forzarla). Solo hace flush: quien llama confirma.
    """
    venta = models.Venta(
        cliente_id=data.cliente_id, sucursal_id=data.sucursal_id, cajero_id=cajero_id,
        canal="presencial", estado="en_conflicto", total=0,
    )
    db.add(venta)
    db.flush()
    total = 0.0
    for item_data in data.items:
        producto = db.get(Producto, item_data.producto_id)
        if not producto:
            raise HTTPException(status_code=404, detail=f"Producto {item_data.producto_id} no encontrado")
        precio = float(producto.precio)
        db.add(models.VentaItem(
            venta_id=venta.id, producto_id=item_data.producto_id, talla_id=item_data.talla_id,
            color_id=item_data.color_id, cantidad=item_data.cantidad, precio_unitario=precio,
        ))
        total += precio * item_data.cantidad
    venta.total = total
    db.flush()
    return venta


def crear_venta_presencial(db: Session, data: schemas.VentaPresencialCreate, cajero_id: int, commit: bool = True) -> models.Venta:
    """Crea una venta presencial atómica: crea venta + items + descuenta stock + registra movimientos.

    Con `commit=False` no confirma la transacción (solo hace flush): quien llama decide cuándo guardar. La
    sincronización móvil lo usa para guardar la venta y su registro de idempotencia juntos.
    """
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
        db.flush()  # sin autoflush, populate_existing descartaria este descuento si el producto se repite en la venta

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

    # 3. Canje de puntos (CU17): baja el total y resta los puntos en esta misma transacción
    if data.puntos_a_canjear > 0:
        total -= fidelizacion.aplicar_canje(
            db, empresa_id=_empresa_de_sucursal(db, data.sucursal_id), cliente_id=data.cliente_id,
            puntos=data.puntos_a_canjear, total=total, venta_id=venta.id,
        )

    # 4. Actualizar total
    venta.total = round(total, 2)
    if not commit:
        db.flush()
        return venta
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

    # Canje de puntos (CU17): baja el total y resta los puntos; si se cancela la venta, los puntos vuelven
    if data.puntos_a_canjear > 0:
        total -= fidelizacion.aplicar_canje(
            db, empresa_id=sucursal.empresa_id, cliente_id=cliente_id,
            puntos=data.puntos_a_canjear, total=total, venta_id=venta.id,
        )

    venta.total = round(total, 2)
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
    # Bloqueo en orden estable (producto, talla, color) para evitar interbloqueos entre ventas concurrentes
    for item in sorted(venta.items, key=lambda i: (i.producto_id, i.talla_id or 0, i.color_id or 0)):
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
