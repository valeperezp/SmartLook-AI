"""Lógica de negocio del módulo Reservas."""
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.suscripciones.service import notificar_llegada
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.reservas import models, schemas


def _ajustar_stock_reserva(
    db: Session,
    producto_id: int,
    talla_id: int | None,
    color_id: int | None,
    sucursal_id: int,
    cantidad: int,
    liberar: bool = False,
):
    """
    Mueve stock entre cantidad_disponible y cantidad_reservada.
    Si liberar=False: reserva (disponible -> reservada).
    Si liberar=True: cancela (reservada -> disponible).
    """
    query = db.query(Inventario).filter(
        Inventario.producto_id == producto_id,
        Inventario.sucursal_id == sucursal_id,
        Inventario.activo.is_(True),
    )
    if talla_id is not None:
        query = query.filter(Inventario.talla_id == talla_id)
    if color_id is not None:
        query = query.filter(Inventario.color_id == color_id)

    # Bloqueo de fila: reservar, cancelar y atender sobre el mismo inventario se serializan
    inventario = query.with_for_update().populate_existing().first()
    if not inventario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No hay inventario para el producto {producto_id} en la sucursal {sucursal_id}",
        )

    if liberar:
        inventario.cantidad_reservada = max(0, inventario.cantidad_reservada - cantidad)
        inventario.cantidad_disponible += cantidad
        notificar_llegada(db, inventario)  # CU16: la reserva cancelada devolvió stock
    else:
        if inventario.cantidad_disponible < cantidad:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Stock insuficiente para el producto {inventario.nombre_producto}. "
                       f"Disponible: {inventario.cantidad_disponible}, solicitado: {cantidad}",
            )
        inventario.cantidad_disponible -= cantidad
        inventario.cantidad_reservada += cantidad

    # populate_existing + autoflush desactivado: sin flush, un producto repetido en la misma operacion
    # recargaria el valor de BD y perderia este cambio.
    db.flush()
    return inventario


def crear_reserva(db: Session, data: schemas.ReservaCreate, cliente_id: int, commit: bool = True) -> models.Reserva:
    """Crea una reserva con sus items y ajusta el stock. Con `commit=False` solo hace flush (decide quien llama)."""
    reserva = models.Reserva(
        cliente_id=cliente_id,
        sucursal_id=data.sucursal_id,
        horario_aproximado=data.horario_aproximado,
        estado="pendiente",
    )
    db.add(reserva)
    db.flush()  # Para obtener el ID sin commitear

    # Orden estable (producto, talla, color), igual que en ventas, para evitar interbloqueos
    for item_data in sorted(data.items, key=lambda i: (i.producto_id, i.talla_id or 0, i.color_id or 0)):
        _ajustar_stock_reserva(
            db=db,
            producto_id=item_data.producto_id,
            talla_id=item_data.talla_id,
            color_id=item_data.color_id,
            sucursal_id=data.sucursal_id,
            cantidad=item_data.cantidad,
            liberar=False,
        )
        item = models.ReservaItem(
            reserva_id=reserva.id,
            producto_id=item_data.producto_id,
            talla_id=item_data.talla_id,
            color_id=item_data.color_id,
            cantidad=item_data.cantidad,
        )
        db.add(item)

    if not commit:
        db.flush()
        return reserva
    db.commit()
    db.refresh(reserva)
    return reserva


def listar_mis_reservas(db: Session, cliente_id: int) -> list[models.Reserva]:
    """Lista las reservas del cliente autenticado."""
    return (
        db.query(models.Reserva)
        .options(
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.producto),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.talla),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.color),
            joinedload(models.Reserva.sucursal),
            joinedload(models.Reserva.cliente),
        )
        .filter(models.Reserva.cliente_id == cliente_id)
        .order_by(models.Reserva.creada_en.desc())
        .all()
    )


def obtener_reserva(
    db: Session, reserva_id: int, cliente_id: int | None = None
) -> models.Reserva | None:
    """Obtiene una reserva por ID. Si cliente_id se pasa, valida que sea el dueño."""
    query = (
        db.query(models.Reserva)
        .options(
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.producto),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.talla),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.color),
            joinedload(models.Reserva.sucursal),
            joinedload(models.Reserva.cliente),
        )
        .filter(models.Reserva.id == reserva_id)
    )
    if cliente_id is not None:
        query = query.filter(models.Reserva.cliente_id == cliente_id)
    return query.first()


def cancelar_reserva(db: Session, reserva_id: int, cliente_id: int) -> models.Reserva | None:
    """Cancela una reserva y devuelve el stock a disponible."""
    reserva = obtener_reserva(db, reserva_id, cliente_id)
    if not reserva:
        return None
    if reserva.estado == "cancelada":
        raise HTTPException(status_code=400, detail="La reserva ya está cancelada")
    if reserva.estado == "atendida":
        raise HTTPException(status_code=400, detail="No se puede cancelar una reserva ya atendida")

    for item in sorted(reserva.items, key=lambda i: (i.producto_id, i.talla_id or 0, i.color_id or 0)):
        _ajustar_stock_reserva(
            db=db,
            producto_id=item.producto_id,
            talla_id=item.talla_id,
            color_id=item.color_id,
            sucursal_id=reserva.sucursal_id,
            cantidad=item.cantidad,
            liberar=True,
        )

    reserva.estado = "cancelada"
    db.commit()
    db.refresh(reserva)
    return reserva


def listar_reservas_por_sucursal(db: Session, sucursal_id: int) -> list[models.Reserva]:
    """Endpoint para encargado: reservas de una sucursal."""
    return (
        db.query(models.Reserva)
        .options(
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.producto),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.talla),
            joinedload(models.Reserva.items).joinedload(models.ReservaItem.color),
            joinedload(models.Reserva.sucursal),
            joinedload(models.Reserva.cliente),
        )
        .filter(models.Reserva.sucursal_id == sucursal_id)
        .order_by(models.Reserva.creada_en.desc())
        .all()
    )


# =========================================================================
# GESTIÓN DE RESERVAS POR ENCARGADO (CU14)
# =========================================================================

ESTADOS_PERMITIDOS = {
    "pendiente": ["confirmada", "cancelada"],
    "confirmada": ["atendida", "cancelada"],
    "atendida": [],
    "cancelada": [],
}


def validar_transicion_estado(estado_actual: str, nuevo_estado: str) -> None:
    """Valida que la transición de estado sea permitida."""
    if estado_actual not in ESTADOS_PERMITIDOS:
        raise HTTPException(
            status_code=400,
            detail=f"Estado actual desconocido: {estado_actual}",
        )
    if nuevo_estado not in ESTADOS_PERMITIDOS[estado_actual]:
        raise HTTPException(
            status_code=400,
            detail=f"No se puede pasar de '{estado_actual}' a '{nuevo_estado}'. "
                   f"Transiciones permitidas: {ESTADOS_PERMITIDOS[estado_actual]}",
        )


def listar_reservas_mi_sucursal(db: Session, sucursal_id: int) -> list[models.Reserva]:
    """Lista reservas de la sucursal del encargado autenticado."""
    return listar_reservas_por_sucursal(db, sucursal_id)


def cambiar_estado_con_validacion(
    db: Session,
    reserva_id: int,
    nuevo_estado: str,
    sucursal_id: int | None = None,
) -> models.Reserva | None:
    """
    Cambia el estado de una reserva con validación de transición.
    Si sucursal_id se provee, valida que la reserva pertenezca a esa sucursal.
    """
    # Se bloquea la fila: dos cambios de estado simultaneos de la misma reserva se serializan
    # y el segundo falla la validacion de transicion (evita convertir o liberar el stock dos veces).
    reserva = (
        db.query(models.Reserva)
        .filter(models.Reserva.id == reserva_id)
        .with_for_update()
        .populate_existing()
        .first()
    )
    if not reserva:
        return None

    if sucursal_id is not None and reserva.sucursal_id != sucursal_id:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para gestionar reservas de otra sucursal",
        )

    validar_transicion_estado(reserva.estado, nuevo_estado)

    # Si se cancela, revertir stock
    if nuevo_estado == "cancelada":
        for item in sorted(reserva.items, key=lambda i: (i.producto_id, i.talla_id or 0, i.color_id or 0)):
            _ajustar_stock_reserva(
                db=db,
                producto_id=item.producto_id,
                talla_id=item.talla_id,
                color_id=item.color_id,
                sucursal_id=reserva.sucursal_id,
                cantidad=item.cantidad,
                liberar=True,
            )

    # Si se atiende (solo desde 'confirmada', ver ESTADOS_PERMITIDOS), lo reservado pasa a vendido
    if nuevo_estado == "atendida":
        _convertir_reserva_en_venta(db, reserva)

    reserva.estado = nuevo_estado
    db.commit()
    db.refresh(reserva)
    return reserva


def _convertir_reserva_en_venta(db: Session, reserva: models.Reserva) -> None:
    """Mueve el stock de cantidad_reservada a cantidad_vendida y registra el movimiento de inventario."""
    # Bloqueo en orden estable (producto, talla, color) para evitar interbloqueos entre operaciones concurrentes
    for item in sorted(reserva.items, key=lambda i: (i.producto_id, i.talla_id or 0, i.color_id or 0)):
        query = db.query(Inventario).filter(
            Inventario.producto_id == item.producto_id,
            Inventario.sucursal_id == reserva.sucursal_id,
            Inventario.activo.is_(True),
        )
        if item.talla_id is not None:
            query = query.filter(Inventario.talla_id == item.talla_id)
        if item.color_id is not None:
            query = query.filter(Inventario.color_id == item.color_id)

        inventario = query.with_for_update().populate_existing().first()
        if not inventario:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"No hay inventario para el producto {item.producto_id} en la sucursal {reserva.sucursal_id}",
            )

        inventario.cantidad_reservada = max(0, inventario.cantidad_reservada - item.cantidad)
        inventario.cantidad_vendida += item.cantidad
        db.add(
            MovimientoInventario(
                inventario_id=inventario.id,
                tipo="venta",
                cantidad=item.cantidad,
                motivo=f"Reserva #{reserva.id} atendida",
                usuario_id=reserva.cliente_id,
            )
        )


def obtener_reserva_por_sucursal(
    db: Session,
    reserva_id: int,
    sucursal_id: int,
) -> models.Reserva | None:
    """Obtiene una reserva validando que pertenezca a la sucursal."""
    reserva = obtener_reserva(db, reserva_id)
    if not reserva:
        return None
    if reserva.sucursal_id != sucursal_id:
        raise HTTPException(
            status_code=403,
            detail="No tiene permisos para ver reservas de otra sucursal",
        )
    return reserva

