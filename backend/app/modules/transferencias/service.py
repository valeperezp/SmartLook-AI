"""Lógica de transferencias de stock entre sucursales (CU19) — máquina de estados.

    SOLICITADA ──enviar (origen)──▶ EN TRÁNSITO ──confirmar recepción (destino)──▶ RECIBIDA
        │
        ├──rechazar (origen, con motivo)──▶ RECHAZADA
        └──cancelar (destino, antes del envío)──▶ CANCELADA

- El Encargado de destino solicita las prendas a otra sucursal de su empresa.
- enviar:  en una transacción revalida la existencia, descuenta el origen y registra SALIDA POR TRANSFERENCIA.
- recibir: en una transacción suma al destino (lo recibido, si llegan menos se guarda la observación)
           y registra ENTRADA POR TRANSFERENCIA.
Cada transición queda en el historial. ("aprobada" solo existe en transferencias anteriores.)
"""
from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session, joinedload

from app.modules.suscripciones.service import notificar_llegada
from app.modules.catalogo.models import Producto
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.sucursales.models import Sucursal
from app.modules.transferencias import models, schemas
from app.modules.usuarios.models import Usuario
from app.shared.db.tenant import asegurar_de_empresa

# accion -> (estados desde los que se puede, estado al que lleva)
TRANSICIONES: dict[str, tuple[set[str], str]] = {
    "enviar": ({"solicitada", "aprobada"}, "en_transito"),
    "rechazar": ({"solicitada", "aprobada"}, "rechazada"),
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
    if accion in ("enviar", "rechazar"):
        # Quien entrega la mercadería decide si la manda (CU19 paso 6 y 6a).
        return _es_encargado_de(usuario, t.sucursal_origen_id)
    if accion in ("recibir", "cancelar"):
        # El destino la pidió: confirma la recepción o cancela antes del envío (paso 8 y 5a).
        return _es_encargado_de(usuario, t.sucursal_destino_id)
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
    if not _es_admin(usuario) and usuario.sucursal_id != destino.id:
        raise HTTPException(status_code=403, detail="Solo puede solicitar prendas para su propia sucursal")

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
            raise HTTPException(status_code=404, detail="No hay existencia de esa prenda en la sucursal de origen")
        if item.cantidad > inv.cantidad_disponible:  # 4a: se informa lo disponible para ajustar la cantidad
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Existencia insuficiente de {inv.nombre_producto}: hay {inv.cantidad_disponible} "
                    f"disponibles en {origen.nombre} y se piden {item.cantidad}. Ajuste la cantidad."
                ),
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
        if inv.cantidad_disponible < item.cantidad:  # 7a
            raise HTTPException(
                status_code=400,
                detail=(
                    f"Existencia insuficiente de {inv.nombre_producto} en {t.nombre_origen}: "
                    f"hay {inv.cantidad_disponible} disponibles y se piden {item.cantidad}"
                ),
            )
        inv.cantidad_disponible -= item.cantidad
        db.add(MovimientoInventario(
            inventario_id=inv.id, tipo="transferencia_salida", cantidad=item.cantidad, usuario_id=usuario.id,
            motivo=f"Transferencia #{t.id} hacia {t.nombre_destino}",
        ))


def _sumar_destino(db: Session, t: models.Transferencia, usuario: Usuario, recibidas: dict[int, int]) -> None:
    faltantes = []
    for item in t.items:
        origen = item.inventario_origen
        recibida = recibidas.get(item.id, item.cantidad)
        if recibida < 0 or recibida > item.cantidad:
            raise HTTPException(
                status_code=400,
                detail=f"{origen.nombre_producto}: la cantidad recibida debe estar entre 0 y {item.cantidad}",
            )
        item.cantidad_recibida = recibida
        if recibida < item.cantidad:
            faltantes.append(f"{origen.nombre_producto}: llegaron {recibida} de {item.cantidad}")
        if recibida == 0:
            continue
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
        inv.cantidad_disponible += recibida
        notificar_llegada(db, inv)  # CU16: llegó stock a esta sucursal
        db.add(MovimientoInventario(
            inventario_id=inv.id, tipo="transferencia_entrada", cantidad=recibida, usuario_id=usuario.id,
            motivo=f"Transferencia #{t.id} desde {t.nombre_origen}",
        ))
    if faltantes:  # 8a: la diferencia queda como observación de la transferencia
        t.observacion = "Llegaron menos unidades de las enviadas. " + "; ".join(faltantes)


def disponibilidad(
    db: Session, usuario: Usuario, producto_id: int, talla_id: int | None, color_id: int | None
) -> list[dict]:
    """CU19 paso 2: sucursales de la empresa (distintas de la del encargado) con existencia de la variante."""
    asegurar_de_empresa(db, Producto, producto_id, usuario.empresa_id, "Producto")
    query = (
        db.query(Inventario)
        .join(Sucursal, Inventario.sucursal_id == Sucursal.id)
        .filter(
            Sucursal.empresa_id == usuario.empresa_id,
            Sucursal.activa.is_(True),
            Inventario.producto_id == producto_id,
            Inventario.activo.is_(True),
            Inventario.cantidad_disponible > 0,
        )
    )
    if talla_id is not None:
        query = query.filter(Inventario.talla_id == talla_id)
    if color_id is not None:
        query = query.filter(Inventario.color_id == color_id)
    if usuario.sucursal_id is not None:
        query = query.filter(Inventario.sucursal_id != usuario.sucursal_id)
    return [
        {
            "inventario_id": inv.id, "sucursal_id": inv.sucursal_id, "nombre_sucursal": inv.nombre_sucursal,
            "producto_id": inv.producto_id, "nombre_producto": inv.nombre_producto,
            "talla_id": inv.talla_id, "nombre_talla": inv.nombre_talla,
            "color_id": inv.color_id, "nombre_color": inv.nombre_color,
            "cantidad_disponible": inv.cantidad_disponible,
        }
        for inv in query.order_by(Inventario.cantidad_disponible.desc()).all()
    ]


def ejecutar(
    db: Session, usuario: Usuario, transferencia_id: int, accion: str, comentario: str | None,
    recibidas: dict[int, int] | None = None,
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
        raise HTTPException(status_code=403, detail=f"No tiene permiso para {accion} esta transferencia")

    if accion == "rechazar" and not (comentario and comentario.strip()):
        raise HTTPException(status_code=400, detail="Indique el motivo del rechazo")  # 6a
    if accion == "enviar":
        _descontar_origen(db, t, usuario)
    elif accion == "recibir":
        _sumar_destino(db, t, usuario, recibidas or {})
    elif accion == "rechazar":
        t.observacion = f"Motivo del rechazo: {comentario.strip()}"

    t.historial.append(models.TransferenciaHistorial(
        estado_anterior=t.estado, estado_nuevo=hacia, usuario_id=usuario.id, comentario=comentario,
    ))
    t.estado = hacia
    db.commit()
    return obtener(db, usuario, transferencia_id)
