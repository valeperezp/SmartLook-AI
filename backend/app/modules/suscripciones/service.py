"""Lógica de las suscripciones de stock (CU16 — "Avísame cuando llegue").

- El cliente se suscribe a una prenda (producto + talla/color/sucursal opcionales). Queda `pendiente`.
- Cuando entra stock de esa variante, `notificar_llegada` pasa a `notificado` las suscripciones que coinciden. Lo llaman
  todos los lugares que SUMAN stock (entrada de inventario, ajuste hacia arriba, carga inicial, transferencia recibida,
  devolución, reserva cancelada): el aviso no depende de por dónde entró la mercadería.
- Multi-empresa: cada consulta filtra por `empresa_id`; un cliente solo ve y toca sus propias suscripciones.
"""
from datetime import datetime, timezone

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Color, Producto, Talla
from app.modules.inventario.models import Inventario
from app.modules.suscripciones import schemas
from app.modules.suscripciones.models import ESTADO_NOTIFICADO, ESTADO_PENDIENTE, SuscripcionStock
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario


def _ahora() -> datetime:
    return datetime.now(timezone.utc)


# ---------------------------------------------------------------------------------------------------------------
# El disparador: entra stock → se avisa a quien lo esperaba
# ---------------------------------------------------------------------------------------------------------------

def notificar_llegada(db: Session, inv: Inventario) -> int:
    """Pasa a `notificado` las suscripciones pendientes que esperaban esta variante. NO confirma la transacción.

    Coinciden las que piden ese producto y, en talla, color y sucursal, o bien piden esa misma o no piden ninguna en
    particular (NULL = cualquiera). Solo avisa si la variante realmente tiene stock. Devuelve cuántas cambiaron.
    """
    if inv.cantidad_disponible <= 0 or inv.activo is False:
        return 0
    producto = db.get(Producto, inv.producto_id)
    if producto is None:
        return 0
    pendientes = (
        db.query(SuscripcionStock)
        .filter(
            SuscripcionStock.empresa_id == producto.empresa_id,
            SuscripcionStock.producto_id == inv.producto_id,
            SuscripcionStock.estado == ESTADO_PENDIENTE,
            or_(SuscripcionStock.talla_id.is_(None), SuscripcionStock.talla_id == inv.talla_id),
            or_(SuscripcionStock.color_id.is_(None), SuscripcionStock.color_id == inv.color_id),
            or_(SuscripcionStock.sucursal_id.is_(None), SuscripcionStock.sucursal_id == inv.sucursal_id),
        )
        .all()
    )
    ahora = _ahora()
    for s in pendientes:
        s.estado = ESTADO_NOTIFICADO
        s.notificado_en = ahora
        s.visto = False
    if pendientes:
        db.flush()
    return len(pendientes)


# ---------------------------------------------------------------------------------------------------------------
# Cliente
# ---------------------------------------------------------------------------------------------------------------

def _descripcion(producto: Producto, talla: Talla | None, color: Color | None) -> str:
    partes = [producto.nombre]
    if talla:
        partes.append(f"Talla {talla.nombre}")
    if color:
        partes.append(color.nombre)
    return " · ".join(partes)


def _a_salida(db: Session, s: SuscripcionStock) -> schemas.SuscripcionOut:
    producto = db.get(Producto, s.producto_id)
    talla = db.get(Talla, s.talla_id) if s.talla_id else None
    color = db.get(Color, s.color_id) if s.color_id else None
    sucursal = db.get(Sucursal, s.sucursal_id) if s.sucursal_id else None
    nombre = producto.nombre if producto else f"Producto {s.producto_id}"
    return schemas.SuscripcionOut(
        id=s.id, uuid=s.uuid, producto_id=s.producto_id, nombre_producto=nombre,
        talla_id=s.talla_id, nombre_talla=talla.nombre if talla else None,
        color_id=s.color_id, nombre_color=color.nombre if color else None,
        sucursal_id=s.sucursal_id, nombre_sucursal=sucursal.nombre if sucursal else None,
        descripcion=_descripcion(producto, talla, color) if producto else nombre,
        estado=s.estado, fecha=s.fecha.isoformat() if s.fecha else None,
        notificado_en=s.notificado_en.isoformat() if s.notificado_en else None, visto=bool(s.visto),
    )


def _hay_stock_ahora(db: Session, empresa_id: int, data: schemas.SuscripcionCreate) -> bool:
    consulta = (
        db.query(Inventario.id)
        .join(Sucursal, Inventario.sucursal_id == Sucursal.id)
        .filter(Inventario.producto_id == data.producto_id, Inventario.cantidad_disponible > 0, Inventario.activo.is_(True),
                Sucursal.empresa_id == empresa_id)
    )
    if data.talla_id is not None:
        consulta = consulta.filter(Inventario.talla_id == data.talla_id)
    if data.color_id is not None:
        consulta = consulta.filter(Inventario.color_id == data.color_id)
    if data.sucursal_id is not None:
        consulta = consulta.filter(Inventario.sucursal_id == data.sucursal_id)
    return consulta.first() is not None


def suscribir(db: Session, usuario: Usuario, data: schemas.SuscripcionCreate) -> schemas.SuscripcionOut:
    """`POST /suscripciones`. Idempotente: reenviar el mismo uuid, o pedir de nuevo lo mismo, devuelve la que ya existe."""
    empresa_id = usuario.empresa_id
    if empresa_id is None:
        raise HTTPException(status_code=403, detail="Esta acción requiere pertenecer a una empresa")

    # Todo lo que se pide tiene que ser de la empresa del cliente (si no, es como si no existiera)
    if db.query(Producto.id).filter(Producto.id == data.producto_id, Producto.empresa_id == empresa_id).first() is None:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    if data.talla_id is not None and db.query(Talla.id).filter(Talla.id == data.talla_id, Talla.empresa_id == empresa_id).first() is None:
        raise HTTPException(status_code=404, detail="Talla no encontrada")
    if data.color_id is not None and db.query(Color.id).filter(Color.id == data.color_id, Color.empresa_id == empresa_id).first() is None:
        raise HTTPException(status_code=404, detail="Color no encontrado")
    if data.sucursal_id is not None and db.query(Sucursal.id).filter(Sucursal.id == data.sucursal_id, Sucursal.empresa_id == empresa_id).first() is None:
        raise HTTPException(status_code=404, detail="Sucursal no encontrada")

    # Reintentos: mismo uuid, o ya espera exactamente lo mismo
    if data.uuid:
        previa = db.query(SuscripcionStock).filter(SuscripcionStock.empresa_id == empresa_id, SuscripcionStock.uuid == data.uuid,
                                                   SuscripcionStock.cliente_id == usuario.id).first()
        if previa is not None:
            return _a_salida(db, previa)
    igual = db.query(SuscripcionStock).filter(
        SuscripcionStock.empresa_id == empresa_id, SuscripcionStock.cliente_id == usuario.id, SuscripcionStock.producto_id == data.producto_id,
        SuscripcionStock.talla_id.is_not_distinct_from(data.talla_id), SuscripcionStock.color_id.is_not_distinct_from(data.color_id),
        SuscripcionStock.sucursal_id.is_not_distinct_from(data.sucursal_id), SuscripcionStock.estado == ESTADO_PENDIENTE,
    ).first()
    if igual is not None:
        return _a_salida(db, igual)

    nueva = SuscripcionStock(
        empresa_id=empresa_id, uuid=data.uuid, cliente_id=usuario.id, producto_id=data.producto_id, talla_id=data.talla_id,
        color_id=data.color_id, sucursal_id=data.sucursal_id, estado=ESTADO_PENDIENTE, visto=False,
    )
    # Si ya hay stock (p. ej. una suscripción hecha sin red que llegó tarde) no tiene sentido esperar: se avisa de una vez
    if _hay_stock_ahora(db, empresa_id, data):
        nueva.estado, nueva.notificado_en = ESTADO_NOTIFICADO, _ahora()
    db.add(nueva)
    db.commit()
    db.refresh(nueva)
    return _a_salida(db, nueva)


def _de_mi_cuenta(db: Session, usuario: Usuario):
    return db.query(SuscripcionStock).filter(SuscripcionStock.empresa_id == usuario.empresa_id, SuscripcionStock.cliente_id == usuario.id)


def mis_suscripciones(db: Session, usuario: Usuario) -> list[schemas.SuscripcionOut]:
    filas = _de_mi_cuenta(db, usuario).order_by(SuscripcionStock.fecha.desc(), SuscripcionStock.id.desc()).all()
    return [_a_salida(db, s) for s in filas]


def mis_notificaciones(db: Session, usuario: Usuario, solo_nuevas: bool = False) -> list[schemas.SuscripcionOut]:
    """Las suscripciones cuyo producto ya llegó (`notificado`). Con [solo_nuevas], las que el cliente aún no vio."""
    consulta = _de_mi_cuenta(db, usuario).filter(SuscripcionStock.estado == ESTADO_NOTIFICADO)
    if solo_nuevas:
        consulta = consulta.filter(SuscripcionStock.visto.is_(False))
    return [_a_salida(db, s) for s in consulta.order_by(SuscripcionStock.notificado_en.desc(), SuscripcionStock.id.desc()).all()]


def marcar_vistas(db: Session, usuario: Usuario) -> int:
    """El cliente ya vio sus avisos: no se vuelven a mostrar como nuevos."""
    filas = _de_mi_cuenta(db, usuario).filter(SuscripcionStock.estado == ESTADO_NOTIFICADO, SuscripcionStock.visto.is_(False)).all()
    for s in filas:
        s.visto = True
    db.commit()
    return len(filas)
