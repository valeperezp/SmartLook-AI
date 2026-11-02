"""Lógica de transferencias de stock entre sucursales (CU19) — máquina de estados.

    solicitada ──aprobar──▶ aprobada ──despachar──▶ en_transito ──recibir──▶ recibida
        │                      │
        ├──rechazar──▶ rechazada
        └──cancelar──▶ cancelada ◀──cancelar──┘

- despachar: descuenta el stock de la sucursal de origen (con bloqueo de fila).
- recibir:   suma el stock en la sucursal de destino (crea el registro si no existe).
Cada transición queda en el historial y genera movimientos de inventario.
"""
from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.sucursales.models import Sucursal
from app.modules.transferencias import models, schemas
from app.modules.usuarios.models import Usuario
from app.shared.db.tenant import asegurar_de_empresa

# accion -> (estados desde los que se puede, estado al que lleva)
TRANSICIONES: dict[str, tuple[set[str], str]] = {
    "aprobar": ({"solicitada"}, "aprobada"),
    "rechazar": ({"solicitada"}, "rechazada"),
    "despachar": ({"aprobada"}, "en_transito"),
    "recibir": ({"en_transito"}, "recibida"),
    "cancelar": ({"solicitada", "aprobada"}, "cancelada"),
}


# ---------------------------------------------------------------- permisos

def _es_admin(usuario: Usuario) -> bool:
    return usuario.rol == "administrador"


def _es_encargado_de(usuario: Usuario, sucursal_id: int) -> bool:
    return usuario.rol == "encargado_sucursal" and usuario.sucursal_id == sucursal_id


def puede(usuario: Usuario, accion: str, t: models.Transferencia) -> bool:
    """¿Este usuario puede ejecutar `accion` sobre la transferencia en su estado actual?"""
    desde, _ = TRANSICIONES[accion]
    if t.estado not in desde:
        return False
    if _es_admin(usuario):
        return True
    if accion in ("aprobar", "rechazar", "despachar"):
        # Quien entrega la mercadería decide si la manda.
        return _es_encargado_de(usuario, t.sucursal_origen_id)
    if accion == "recibir":
        return _es_encargado_de(usuario, t.sucursal_destino_id)
    if accion == "cancelar":
        # El solicitante puede arrepentirse mientras nadie la aprobó.
        return t.estado == "solicitada" and t.solicitado_por_id == usuario.id
    return False


def acciones_disponibles(usuario: Usuario, t: models.Transferencia) -> list[str]:
    return [accion for accion in TRANSICIONES if puede(usuario, accion, t)]


def _puede_ver(usuario: Usuario, t: models.Transferencia) -> bool:
    if _es_admin(usuario):
        return True
    return usuario.sucursal_id in (t.sucursal_origen_id, t.sucursal_destino_id)


# ---------------------------------------------------------------- consultas

def _query(db: Session, empresa_id: int):
    return (
        db.query(models.Transferencia)
        .options(
            joinedload(models.Transferencia.sucursal_origen),
            joinedload(models.Transferencia.sucursal_destino),
            joinedload(models.Transferencia.solicitado_por),
            joinedload(models.Transferencia.items).joinedload(models.TransferenciaItem.inventario_origen),
            joinedload(models.Transferencia.historial).joinedload(models.TransferenciaHistorial.usuario),
        )
        .filter(models.Transferencia.empresa_id == empresa_id)
    )


def listar(db: Session, usuario: Usuario, estado: str | None = None) -> list[models.Transferencia]:
    query = _query(db, usuario.empresa_id)
    if not _es_admin(usuario):
        # El encargado ve lo que sale de su sucursal o lo que llega a ella.
        query = query.filter(
            or_(
                models.Transferencia.sucursal_origen_id == usuario.sucursal_id,
                models.Transferencia.sucursal_destino_id == usuario.sucursal_id,
            )
        )
    if estado:
        query = query.filter(models.Transferencia.estado == estado)
    return query.order_by(models.Transferencia.id.desc()).all()


def obtener(db: Session, usuario: Usuario, transferencia_id: int) -> models.Transferencia:
    t = _query(db, usuario.empresa_id).filter(models.Transferencia.id == transferencia_id).first()
    if t is None or not _puede_ver(usuario, t):
        raise HTTPException(status_code=404, detail="Transferencia no encontrada")
    return t


def a_salida(usuario: Usuario, t: models.Transferencia) -> schemas.TransferenciaOut:
    salida = schemas.TransferenciaOut.model_validate(t)
    salida.acciones = acciones_disponibles(usuario, t)
    return salida


# ---------------------------------------------------------------- alta

def crear(db: Session, usuario: Usuario, data: schemas.TransferenciaCreate) -> models.Transferencia:
    empresa_id = usuario.empresa_id
    if data.sucursal_origen_id == data.sucursal_destino_id:
        raise HTTPException(status_code=400, detail="El origen y el destino deben ser sucursales distintas")
    origen = asegurar_de_empresa(db, Sucursal, data.sucursal_origen_id, empresa_id, "Sucursal de origen")
    destino = asegurar_de_empresa(db, Sucursal, data.sucursal_destino_id, empresa_id, "Sucursal de destino")
    if not origen.activa or not destino.activa:
        raise HTTPException(status_code=400, detail="Ambas sucursales deben estar activas")
    if not _es_admin(usuario) and usuario.sucursal_id not in (origen.id, destino.id):
        raise HTTPException(status_code=403, detail="Solo podés crear transferencias que involucren a tu sucursal")

    ids = [item.inventario_id for item in data.items]
    if len(ids) != len(set(ids)):
        raise HTTPException(status_code=400, detail="Hay prendas repetidas: sumá las cantidades en una sola línea")

    transferencia = models.Transferencia(
        empresa_id=empresa_id,
        sucursal_origen_id=origen.id,
        sucursal_destino_id=destino.id,
        estado="solicitada",
        motivo=data.motivo,
        solicitado_por_id=usuario.id,
    )
    for item in data.items:
        inv = (
            db.query(Inventario)
            .filter(Inventario.id == item.inventario_id, Inventario.sucursal_id == origen.id, Inventario.activo.is_(True))
            .first()
        )
        if inv is None:
            raise HTTPException(status_code=404, detail=f"La prenda {item.inventario_id} no está en el inventario del origen")
        if item.cantidad > inv.cantidad_disponible:
            raise HTTPException(
                status_code=400,
                detail=f"{inv.nombre_producto}: hay {inv.cantidad_disponible} disponibles en {origen.nombre}, se piden {item.cantidad}",
            )
        transferencia.items.append(models.TransferenciaItem(inventario_origen_id=inv.id, cantidad=item.cantidad))

    transferencia.historial.append(
        models.TransferenciaHistorial(estado_anterior=None, estado_nuevo="solicitada", usuario_id=usuario.id,
                                      comentario=data.motivo)
    )
    db.add(transferencia)
    db.commit()
    return obtener(db, usuario, transferencia.id)


# ---------------------------------------------------------------- transiciones

def _bloquear(db: Session, transferencia_id: int) -> models.Transferencia:
    """Relee la transferencia con bloqueo: dos clics simultáneos no pueden despachar dos veces."""
    return (
        db.query(models.Transferencia)
        .filter(models.Transferencia.id == transferencia_id)
        .with_for_update()
        .populate_existing()
        .one()
    )


def _descontar_origen(db: Session, t: models.Transferencia, usuario: Usuario) -> None:
    for item in t.items:
        inv = (
            db.query(Inventario).filter(Inventario.id == item.inventario_origen_id)
            .with_for_update().populate_existing().one()
        )
        if inv.cantidad_disponible < item.cantidad:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Stock insuficiente de {inv.nombre_producto} en {t.nombre_origen}: "
                    f"hay {inv.cantidad_disponible}, se necesitan {item.cantidad}"
                ),
            )
        inv.cantidad_disponible -= item.cantidad
        db.add(MovimientoInventario(
            inventario_id=inv.id, tipo="transferencia_salida", cantidad=item.cantidad, usuario_id=usuario.id,
            motivo=f"Transferencia #{t.id} hacia {t.nombre_destino}",
        ))


def _sumar_destino(db: Session, t: models.Transferencia, usuario: Usuario) -> None:
    for item in t.items:
        origen = item.inventario_origen
        inv = (
            db.query(Inventario)
            .filter(
                Inventario.sucursal_id == t.sucursal_destino_id,
                Inventario.producto_id == origen.producto_id,
                # IS NOT DISTINCT FROM: una prenda sin talla/color (NULL) también tiene que encontrarse.
                Inventario.talla_id.is_not_distinct_from(origen.talla_id),
                Inventario.color_id.is_not_distinct_from(origen.color_id),
            )
            .with_for_update()
            .first()
        )
        if inv is None:
            # La sucursal de destino nunca tuvo esta prenda: se le crea el registro.
            inv = Inventario(
                producto_id=origen.producto_id, sucursal_id=t.sucursal_destino_id,
                talla_id=origen.talla_id, color_id=origen.color_id,
                cantidad_disponible=0, cantidad_reservada=0, cantidad_vendida=0,
                stock_minimo=origen.stock_minimo, activo=True,
            )
            db.add(inv)
            db.flush()
        inv.activo = True
        inv.cantidad_disponible += item.cantidad
        db.add(MovimientoInventario(
            inventario_id=inv.id, tipo="transferencia_entrada", cantidad=item.cantidad, usuario_id=usuario.id,
            motivo=f"Transferencia #{t.id} desde {t.nombre_origen}",
        ))


def ejecutar(
    db: Session, usuario: Usuario, transferencia_id: int, accion: str, comentario: str | None
) -> models.Transferencia:
    obtener(db, usuario, transferencia_id)  # 404 si no es de su empresa o no la puede ver
    t = _bloquear(db, transferencia_id)
    desde, hacia = TRANSICIONES[accion]
    if t.estado not in desde:
        raise HTTPException(
            status_code=409,
            detail=f"No se puede {accion} una transferencia en estado '{t.estado}'",
        )
    if not puede(usuario, accion, t):
        raise HTTPException(status_code=403, detail=f"No tenés permiso para {accion} esta transferencia")

    if accion == "despachar":
        _descontar_origen(db, t, usuario)
    elif accion == "recibir":
        _sumar_destino(db, t, usuario)

    t.historial.append(models.TransferenciaHistorial(
        estado_anterior=t.estado, estado_nuevo=hacia, usuario_id=usuario.id, comentario=comentario,
    ))
    t.estado = hacia
    db.commit()
    return obtener(db, usuario, transferencia_id)
