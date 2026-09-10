"""Lógica de negocio del módulo Reservas."""
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, joinedload

from app.modules.inventario.models import Inventario
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

    inventario = query.first()
    if not inventario:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"No hay inventario para el producto {producto_id} en la sucursal {sucursal_id}",
        )

    if liberar:
        inventario.cantidad_reservada = max(0, inventario.cantidad_reservada - cantidad)
        inventario.cantidad_disponible += cantidad
    else:
        if inventario.cantidad_disponible < cantidad:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Stock insuficiente para el producto {inventario.nombre_producto}. "
                       f"Disponible: {inventario.cantidad_disponible}, solicitado: {cantidad}",
            )
        inventario.cantidad_disponible -= cantidad
        inventario.cantidad_reservada += cantidad

    return inventario


def crear_reserva(db: Session, data: schemas.ReservaCreate, cliente_id: int) -> models.Reserva:
    """Crea una reserva con sus items y ajusta el stock."""
    reserva = models.Reserva(
        cliente_id=cliente_id,
        sucursal_id=data.sucursal_id,
        horario_aproximado=data.horario_aproximado,
        estado="pendiente",
    )
    db.add(reserva)
    db.flush()  # Para obtener el ID sin commitear

    for item_data in data.items:
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

    for item in reserva.items:
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
        )
        .filter(models.Reserva.sucursal_id == sucursal_id)
        .order_by(models.Reserva.creada_en.desc())
        .all()
    )


def cambiar_estado(db: Session, reserva_id: int, nuevo_estado: str) -> models.Reserva | None:
    """Cambiar estado (encargado/admin)."""
    reserva = db.query(models.Reserva).filter(models.Reserva.id == reserva_id).first()
    if reserva:
        reserva.estado = nuevo_estado
        db.commit()
        db.refresh(reserva)
    return reserva
