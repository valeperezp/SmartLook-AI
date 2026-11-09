"""Lógica de cambios y devoluciones (CU11), compartida por la web (REST) y la sincronización de la app móvil.

Reglas (las manda SIEMPRE el servidor; las apps solo las estiman):
- Plazo: una venta solo admite cambios/devoluciones durante `plazo_dias` desde que se hizo (7 por defecto; cada empresa
  puede configurarlo). Pasado el plazo se rechaza ("El plazo para cambios ha vencido").
- Cantidades: no se puede devolver más de lo vendido, descontando lo ya devuelto en cambios/devoluciones anteriores.
- Lo devuelto vuelve al inventario y se reembolsa al precio de la venta original; lo nuevo (en un cambio) se descuenta
  del inventario al precio vigente. Todo en la misma transacción: si algo falla no queda nada a medias.
"""
import os
import uuid as uuid_lib
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.modules.bitacora import service as bitacora
from app.modules.catalogo.models import Color, Producto, Talla
from app.modules.devoluciones import schemas
from app.modules.devoluciones.models import ConfiguracionDevoluciones, Reembolso
from app.modules.inventario.models import MovimientoInventario
from app.modules.reservas.models import Reserva
from app.modules.sucursales.models import Sucursal
from app.modules.suscripciones.service import notificar_llegada
from app.modules.sync.models import Devolucion, DevolucionItem, SyncOperacion
from app.modules.usuarios.models import Usuario
from app.modules.ventas import service as ventas_service
from app.modules.ventas.models import Venta, VentaItem
from app.shared.core.config import settings
from app.shared.utils.imagenes import validar_imagen

PLAZO_POR_DEFECTO_DIAS = 7
MENSAJE_PLAZO = "El plazo para cambios ha vencido"
ROLES_DEVOLUCION = ("cajero", "encargado_sucursal", "administrador")


class DevolucionError(Exception):
    """La devolución no se puede registrar (el mensaje se devuelve tal cual a quien la pidió)."""


class PlazoVencido(DevolucionError):
    """Pasaron más días desde la venta que los que admite la empresa."""


# ---------------------------------------------------------------------------------------------------------------
# Plazo
# ---------------------------------------------------------------------------------------------------------------

def plazo_dias(db: Session, empresa_id: int | None) -> int:
    if empresa_id is not None:
        config = db.get(ConfiguracionDevoluciones, empresa_id)
        if config is not None and config.plazo_dias > 0:
            return config.plazo_dias
    return PLAZO_POR_DEFECTO_DIAS


def guardar_plazo(db: Session, empresa_id: int, dias: int) -> int:
    config = db.get(ConfiguracionDevoluciones, empresa_id)
    if config is None:
        db.add(ConfiguracionDevoluciones(empresa_id=empresa_id, plazo_dias=dias))
    else:
        config.plazo_dias = dias
    db.flush()
    return dias


def _con_zona(fecha: datetime) -> datetime:
    return fecha if fecha.tzinfo is not None else fecha.replace(tzinfo=timezone.utc)


def dias_desde_la_venta(venta: Venta, ahora: datetime) -> int:
    return max((_con_zona(ahora) - _con_zona(venta.creada_en)).days, 0)


def validar_plazo(db: Session, empresa_id: int, venta: Venta, ahora: datetime) -> None:
    """Compara la fecha de la devolución con la de la venta original; fuera de plazo lanza [PlazoVencido]."""
    dias = plazo_dias(db, empresa_id)
    if _con_zona(ahora) - _con_zona(venta.creada_en) > timedelta(days=dias):
        raise PlazoVencido(MENSAJE_PLAZO)


# ---------------------------------------------------------------------------------------------------------------
# Núcleo: aplica un cambio/devolución a una venta (lo usan la web y la sincronización móvil)
# ---------------------------------------------------------------------------------------------------------------

def _agrupar(items) -> dict[tuple, dict]:
    """Suma las cantidades de la misma prenda (producto + talla + color)."""
    grupos: dict[tuple, dict] = {}
    for i in items:
        if i.cantidad < 1:
            raise DevolucionError(f"Cantidad inválida para el producto {i.producto_id}")
        clave = (i.producto_id, i.talla_id or 0, i.color_id or 0)
        if clave in grupos:
            grupos[clave]["cantidad"] += i.cantidad
        else:
            grupos[clave] = {"producto_id": i.producto_id, "talla_id": i.talla_id, "color_id": i.color_id, "cantidad": i.cantidad}
    return grupos


def cantidades_devueltas(db: Session, venta_id: int) -> dict[tuple, int]:
    """Unidades ya devueltas de cada prenda de la venta (cambios y devoluciones anteriores)."""
    filas = (
        db.query(DevolucionItem.producto_id, DevolucionItem.talla_id, DevolucionItem.color_id, func.sum(DevolucionItem.cantidad))
        .join(Devolucion, Devolucion.id == DevolucionItem.devolucion_id)
        .filter(Devolucion.venta_id == venta_id, DevolucionItem.tipo_item == "devuelto")
        .group_by(DevolucionItem.producto_id, DevolucionItem.talla_id, DevolucionItem.color_id)
        .all()
    )
    devueltas: dict[tuple, int] = defaultdict(int)
    for pid, tid, cid, cant in filas:
        devueltas[(pid, tid or 0, cid or 0)] += int(cant)
    return devueltas


def _vendidas(venta: Venta) -> dict[tuple, dict]:
    vendidas: dict[tuple, dict] = {}
    for vi in venta.items:
        clave = (vi.producto_id, vi.talla_id or 0, vi.color_id or 0)
        linea = vendidas.setdefault(clave, {"item": vi, "cantidad": 0})
        linea["cantidad"] += vi.cantidad
    return vendidas


def aplicar_devolucion(
    db: Session, usuario: Usuario, venta: Venta, *, uuid: str, tipo: str, motivo: str | None, turno_uuid: str | None,
    fecha: datetime | None, items_devueltos, items_nuevos, ahora: datetime,
) -> Devolucion:
    """Registra el cambio/devolución SIN confirmar la transacción. Lanza [DevolucionError] si alguna regla se rompe.

    [ahora] es el momento contra el que se mide el plazo: el reloj del servidor en la web y la fecha en que el
    dispositivo hizo la devolución en la sincronización móvil (así una devolución válida hecha sin red no se rechaza
    solo porque se sincronizó tarde).
    """
    empresa_id = usuario.empresa_id
    validar_plazo(db, empresa_id, venta, ahora)
    if not items_devueltos:
        raise DevolucionError("Hay que devolver al menos una prenda")

    devueltos = _agrupar(items_devueltos)
    nuevos = _agrupar(items_nuevos)

    # Lo que se puede devolver: lo vendido menos lo ya devuelto en cambios/devoluciones anteriores de esa venta
    vendidas = _vendidas(venta)
    ya = cantidades_devueltas(db, venta.id)
    for clave, g in devueltos.items():
        linea = vendidas.get(clave)
        if linea is None:
            raise DevolucionError("Una de las prendas no pertenece a la venta original")
        maximo = linea["cantidad"] - ya.get(clave, 0)
        if g["cantidad"] > maximo:
            raise DevolucionError(f"De '{linea['item'].nombre_producto}' solo se pueden devolver {max(maximo, 0)} unidad(es)")
    for pid in {g["producto_id"] for g in nuevos.values()}:
        if db.query(Producto.id).filter(Producto.id == pid, Producto.empresa_id == empresa_id).first() is None:
            raise DevolucionError(f"Producto {pid} no encontrado en tu empresa")

    dev = Devolucion(
        empresa_id=empresa_id, uuid=uuid, venta_id=venta.id, sucursal_id=venta.sucursal_id, cajero_id=usuario.id,
        tipo=(tipo or "cambio")[:30], motivo=(motivo or None) and motivo[:255], turno_uuid=turno_uuid, fecha=fecha,
    )
    db.add(dev)
    db.flush()

    # 1) Lo devuelto vuelve a la estantería (primero, así un cambio por la misma prenda no choca con stock 0)
    total_devuelto = Decimal(0)
    for clave in sorted(devueltos):
        g, vi = devueltos[clave], vendidas[clave]["item"]
        inventario = ventas_service._buscar_inventario(db, vi.producto_id, venta.sucursal_id, vi.talla_id, vi.color_id)
        if inventario is None:
            raise DevolucionError(f"No hay inventario de '{vi.nombre_producto}' en esta sucursal")
        inventario.cantidad_disponible += g["cantidad"]
        inventario.cantidad_vendida = max(0, inventario.cantidad_vendida - g["cantidad"])
        notificar_llegada(db, inventario)  # CU16: lo devuelto vuelve a la estantería
        db.flush()
        db.add(MovimientoInventario(inventario_id=inventario.id, tipo="devolucion", cantidad=g["cantidad"],
                                    motivo=f"Devolución #{dev.id} de la venta #{venta.id}", usuario_id=usuario.id))
        precio = Decimal(str(vi.precio_unitario))  # se reembolsa al precio de la venta original
        db.add(DevolucionItem(devolucion_id=dev.id, tipo_item="devuelto", producto_id=vi.producto_id, talla_id=vi.talla_id,
                              color_id=vi.color_id, cantidad=g["cantidad"], precio_unitario=precio))
        total_devuelto += precio * g["cantidad"]

    # 2) Lo nuevo (en un cambio) se descuenta del inventario al precio vigente
    total_nuevo = Decimal(0)
    for clave in sorted(nuevos):
        g = nuevos[clave]
        producto = db.query(Producto).filter(Producto.id == g["producto_id"]).first()
        inventario = ventas_service._buscar_inventario(db, g["producto_id"], venta.sucursal_id, g["talla_id"], g["color_id"])
        if inventario is None:
            raise DevolucionError(f"No hay inventario de '{producto.nombre}' en esta sucursal")
        if inventario.cantidad_disponible < g["cantidad"]:
            raise DevolucionError(f"Stock insuficiente para '{producto.nombre}'. Disponible: {inventario.cantidad_disponible}, solicitado: {g['cantidad']}")
        inventario.cantidad_disponible -= g["cantidad"]
        inventario.cantidad_vendida += g["cantidad"]
        db.flush()
        db.add(MovimientoInventario(inventario_id=inventario.id, tipo="venta", cantidad=g["cantidad"],
                                    motivo=f"Cambio #{dev.id} de la venta #{venta.id}", usuario_id=usuario.id))
        precio = Decimal(str(producto.precio))
        db.add(DevolucionItem(devolucion_id=dev.id, tipo_item="nuevo", producto_id=g["producto_id"], talla_id=g["talla_id"],
                              color_id=g["color_id"], cantidad=g["cantidad"], precio_unitario=precio))
        total_nuevo += precio * g["cantidad"]

    dev.total_devuelto = total_devuelto
    dev.total_nuevo = total_nuevo
    db.flush()
    return dev


# ---------------------------------------------------------------------------------------------------------------
# Web (REST)
# ---------------------------------------------------------------------------------------------------------------

def _venta_de_la_empresa(db: Session, usuario: Usuario, venta_id: int) -> Venta:
    """La venta, si es de la empresa (y, para cajero/encargado, de su sucursal). Si no, es como si no existiera."""
    venta = (
        db.query(Venta)
        .join(Sucursal, Venta.sucursal_id == Sucursal.id)
        .options(joinedload(Venta.items).joinedload(VentaItem.producto), joinedload(Venta.items).joinedload(VentaItem.talla),
                 joinedload(Venta.items).joinedload(VentaItem.color), joinedload(Venta.sucursal))
        .filter(Venta.id == venta_id, Sucursal.empresa_id == usuario.empresa_id)
        .first()
    )
    if venta is None or (usuario.rol in ("cajero", "encargado_sucursal") and venta.sucursal_id != usuario.sucursal_id):
        raise HTTPException(status_code=404, detail="Venta no encontrada")
    return venta


def _a_venta_devolvible(db: Session, usuario: Usuario, venta: Venta) -> schemas.VentaDevolvibleOut:
    ya = cantidades_devueltas(db, venta.id)
    registro = db.query(SyncOperacion).filter(
        SyncOperacion.empresa_id == usuario.empresa_id, SyncOperacion.entidad == "venta", SyncOperacion.entidad_id == venta.id,
    ).first()
    ahora = datetime.now(timezone.utc)
    dias, plazo = dias_desde_la_venta(venta, ahora), plazo_dias(db, usuario.empresa_id)
    items = []
    for clave, linea in _vendidas(venta).items():
        vi = linea["item"]
        devuelta = ya.get(clave, 0)
        items.append(schemas.ItemVentaDevolvible(
            producto_id=vi.producto_id, nombre_producto=vi.nombre_producto, talla_id=vi.talla_id, nombre_talla=vi.nombre_talla,
            color_id=vi.color_id, nombre_color=vi.nombre_color, cantidad_vendida=linea["cantidad"], cantidad_devuelta=devuelta,
            cantidad_devolvible=max(linea["cantidad"] - devuelta, 0), precio_unitario=float(vi.precio_unitario),
        ))
    return schemas.VentaDevolvibleOut(
        venta_id=venta.id, uuid=registro.uuid if registro else None,
        recibo=registro.uuid[:8].upper() if registro else f"#{venta.id}", sucursal_id=venta.sucursal_id,
        nombre_sucursal=venta.nombre_sucursal, estado=venta.estado, total=float(venta.total),
        creada_en=_con_zona(venta.creada_en).isoformat(), plazo_dias=plazo, dias_transcurridos=dias,
        dentro_de_plazo=(_con_zona(ahora) - _con_zona(venta.creada_en)) <= timedelta(days=plazo), items=items,
    )


def buscar_venta(db: Session, usuario: Usuario, texto: str) -> schemas.VentaDevolvibleOut:
    """Busca la venta por número de ticket (`123` o `#123`) o por el UUID/recibo con el que la app móvil la mandó."""
    q = (texto or "").strip().lstrip("#")
    if not q:
        raise HTTPException(status_code=400, detail="Escribe el número de ticket o el UUID de la venta")
    venta_id: int | None = None
    if q.isdigit():
        venta_id = int(q)
    else:
        registro = (
            db.query(SyncOperacion)
            .filter(SyncOperacion.empresa_id == usuario.empresa_id, SyncOperacion.entidad == "venta", SyncOperacion.estado == "ok",
                    func.lower(SyncOperacion.uuid).like(q.lower() + "%"))
            .order_by(SyncOperacion.id.desc())
            .first()
        )
        venta_id = registro.entidad_id if registro else None
    if venta_id is None:
        raise HTTPException(status_code=404, detail="No se encontró ninguna venta con ese ticket o UUID")
    return _a_venta_devolvible(db, usuario, _venta_de_la_empresa(db, usuario, venta_id))


def _a_salida(db: Session, dev: Devolucion) -> schemas.DevolucionOut:
    items = []
    for it in db.query(DevolucionItem).filter(DevolucionItem.devolucion_id == dev.id).order_by(DevolucionItem.id).all():
        producto = db.get(Producto, it.producto_id)
        talla = db.get(Talla, it.talla_id) if it.talla_id else None
        color = db.get(Color, it.color_id) if it.color_id else None
        items.append(schemas.ItemDevolucionOut(
            tipo_item=it.tipo_item, producto_id=it.producto_id, nombre_producto=producto.nombre if producto else f"Producto {it.producto_id}",
            talla_id=it.talla_id, nombre_talla=talla.nombre if talla else None, color_id=it.color_id,
            nombre_color=color.nombre if color else None, cantidad=it.cantidad, precio_unitario=float(it.precio_unitario),
        ))
    devuelto, nuevo = float(dev.total_devuelto), float(dev.total_nuevo)
    return schemas.DevolucionOut(
        id=dev.id, uuid=dev.uuid, venta_id=dev.venta_id, tipo=dev.tipo, motivo=dev.motivo, total_devuelto=devuelto,
        total_nuevo=nuevo, diferencia=round(nuevo - devuelto, 2), items=items,
    )


def registrar_devolucion(db: Session, usuario: Usuario, data: schemas.DevolucionCreate) -> schemas.DevolucionOut:
    """`POST /devoluciones`: valida (plazo, cantidades, stock), aplica y confirma. Todo o nada."""
    venta = _venta_de_la_empresa(db, usuario, data.venta_id)

    # Reintentar con el mismo uuid no duplica: se devuelve lo ya registrado
    if data.uuid:
        previa = db.query(Devolucion).filter(Devolucion.empresa_id == usuario.empresa_id, Devolucion.uuid == data.uuid).first()
        if previa is not None:
            return _a_salida(db, previa)

    if venta.estado != "completada":
        raise HTTPException(status_code=400, detail="Solo se pueden cambiar o devolver ventas completadas")
    if data.tipo == "devolucion" and data.items_nuevos:
        raise HTTPException(status_code=400, detail="Una devolución no lleva prendas nuevas: usa un cambio")
    if data.tipo == "cambio" and not data.items_nuevos:
        raise HTTPException(status_code=400, detail="Un cambio necesita al menos una prenda nueva")

    ahora = datetime.now(timezone.utc)
    try:
        dev = aplicar_devolucion(
            db, usuario, venta, uuid=data.uuid or f"web-{uuid_lib.uuid4().hex}", tipo=data.tipo, motivo=data.motivo, turno_uuid=None,
            fecha=ahora, items_devueltos=data.items_devueltos, items_nuevos=data.items_nuevos, ahora=ahora,
        )
        bitacora.registrar(db, "devolucion.registrar", f"Venta {venta.id}: {data.tipo} (devuelto {float(dev.total_devuelto):.2f}, nuevo {float(dev.total_nuevo):.2f})", usuario=usuario)
        db.commit()
    except DevolucionError as e:
        db.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    except HTTPException:
        db.rollback()
        raise
    return _a_salida(db, dev)


# ---------------------------------------------------------------------------------------------------------------
# Reembolsos: devolución de DINERO de un pedido (reserva o venta) cancelado
#
# 1. El cliente pide el reembolso de SU pedido cancelado y adjunta su QR bancario (`solicitar_reembolso` + `subir_qr`). Desde la
#    app puede hacerlo sin conexión: la sincronización llama a estas mismas funciones (`commit=False`).
# 2. El personal (cajero / encargado de la sucursal / administrador) ve el QR, transfiere el dinero y lo marca (`procesar_reembolso`):
#    el reembolso queda `reembolsado` y el pedido `reembolsada`.
# Multi-empresa: un pedido o reembolso de otra empresa (o de otro cliente) se trata como si no existiera (404).
# ---------------------------------------------------------------------------------------------------------------

ESTADOS_REEMBOLSABLES = ("cancelada", "reembolso_pendiente")
ESTADO_REEMBOLSADA = "reembolsada"
MAX_QR_BYTES = 5 * 1024 * 1024  # 5 MB: un QR bancario pesa mucho menos


def _buscar_origen(db: Session, empresa_id: int, reserva_id: int | None, venta_id: int | None, bloquear: bool = False):
    """La reserva o venta (de la empresa). Si no existe o es de otra empresa: 404."""
    if (reserva_id is None) == (venta_id is None):
        raise HTTPException(status_code=400, detail="Indica la reserva o la venta (solo una de las dos)")
    if reserva_id is not None:
        modelo = Reserva
        consulta = db.query(Reserva).join(Sucursal, Reserva.sucursal_id == Sucursal.id).filter(
            Reserva.id == reserva_id, Sucursal.empresa_id == empresa_id)
    else:
        modelo = Venta
        consulta = db.query(Venta).join(Sucursal, Venta.sucursal_id == Sucursal.id).filter(
            Venta.id == venta_id, Sucursal.empresa_id == empresa_id)
    if bloquear:  # dos cajeros procesando el mismo reembolso a la vez se serializan: el segundo ya lo ve reembolsado
        consulta = consulta.with_for_update(of=modelo).populate_existing()
    origen = consulta.first()
    if origen is None:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")
    return origen


def _validar_reembolsable(origen) -> None:
    if origen.estado == ESTADO_REEMBOLSADA:
        raise HTTPException(status_code=409, detail="Este pedido ya fue reembolsado")
    if origen.estado not in ESTADOS_REEMBOLSABLES:
        raise HTTPException(status_code=400, detail="Solo se puede reembolsar un pedido cancelado")


def _monto_de(origen) -> Decimal:
    bruto = origen.total_estimado if isinstance(origen, Reserva) else origen.total
    return Decimal(str(bruto)).quantize(Decimal("0.01"))


def _reembolso_de(db: Session, reserva_id: int | None, venta_id: int | None) -> Reembolso | None:
    consulta = db.query(Reembolso)
    consulta = consulta.filter(Reembolso.reserva_id == reserva_id) if reserva_id is not None else consulta.filter(Reembolso.venta_id == venta_id)
    return consulta.first()


def _crear_reembolso(db: Session, empresa_id: int, origen) -> Reembolso:
    es_reserva = isinstance(origen, Reserva)
    reembolso = Reembolso(
        empresa_id=empresa_id, cliente_id=origen.cliente_id, sucursal_id=origen.sucursal_id,
        reserva_id=origen.id if es_reserva else None, venta_id=None if es_reserva else origen.id, monto=_monto_de(origen),
    )
    db.add(reembolso)
    db.flush()
    return reembolso


def solicitar_reembolso(db: Session, usuario: Usuario, reserva_id: int | None = None, venta_id: int | None = None,
                        *, commit: bool = True) -> Reembolso:
    """El cliente pide el reembolso de SU pedido cancelado. Es idempotente: si ya lo pidió devuelve el mismo reembolso."""
    if usuario.rol != "cliente":
        raise HTTPException(status_code=403, detail="Solo un cliente puede pedir el reembolso de su pedido")
    origen = _buscar_origen(db, usuario.empresa_id, reserva_id, venta_id)
    if origen.cliente_id != usuario.id:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")  # el pedido de otro cliente no existe para este
    _validar_reembolsable(origen)
    reembolso = _reembolso_de(db, reserva_id, venta_id)
    if reembolso is None:
        reembolso = _crear_reembolso(db, usuario.empresa_id, origen)
    if commit:
        try:
            db.commit()
        except IntegrityError:  # otra petición lo creó a la vez: se usa ese
            db.rollback()
            reembolso = _reembolso_de(db, reserva_id, venta_id)
            if reembolso is None:
                raise
        else:
            db.refresh(reembolso)
    return reembolso


def _borrar_archivo_qr(ruta_relativa: str | None) -> None:
    if not ruta_relativa:
        return
    try:
        os.remove(os.path.join(settings.uploads_dir, ruta_relativa))
    except OSError:
        pass  # ya no estaba: no importa


def subir_qr(db: Session, usuario: Usuario, reembolso_id: int, contenido: bytes, *, commit: bool = True) -> Reembolso:
    """Guarda el QR bancario del cliente en SU reembolso pendiente. Valida el contenido real de la imagen (PNG/JPG/WEBP)."""
    if usuario.rol != "cliente":
        raise HTTPException(status_code=403, detail="Solo el cliente puede adjuntar el QR de su reembolso")
    reembolso = db.query(Reembolso).filter(
        Reembolso.id == reembolso_id, Reembolso.empresa_id == usuario.empresa_id, Reembolso.cliente_id == usuario.id,
    ).first()
    if reembolso is None:
        raise HTTPException(status_code=404, detail="Reembolso no encontrado")
    if reembolso.estado != "pendiente":
        raise HTTPException(status_code=409, detail="Este reembolso ya fue procesado")
    _, extension = validar_imagen(contenido, MAX_QR_BYTES)  # tamaño y firma del archivo; la extensión sale del contenido

    relativo = f"qr_devolucion/reembolso_{reembolso.id}_{uuid_lib.uuid4().hex}.{extension}"
    absoluto = os.path.join(settings.uploads_dir, relativo)
    os.makedirs(os.path.dirname(absoluto), exist_ok=True)
    with open(absoluto, "wb") as archivo:
        archivo.write(contenido)

    anterior = reembolso.qr_devolucion_path
    reembolso.qr_devolucion_path = relativo
    reembolso.qr_subido_en = datetime.now(timezone.utc)
    if commit:
        db.commit()
        db.refresh(reembolso)
        _borrar_archivo_qr(anterior)  # el QR anterior (si lo cambió) ya no sirve
    else:
        db.flush()
    return reembolso


def listar_mis_reembolsos(db: Session, usuario: Usuario) -> list[Reembolso]:
    return (
        db.query(Reembolso)
        .filter(Reembolso.empresa_id == usuario.empresa_id, Reembolso.cliente_id == usuario.id)
        .order_by(Reembolso.creado_en.desc(), Reembolso.id.desc())
        .all()
    )


def listar_reembolsos(db: Session, usuario: Usuario, estado: str | None = None) -> list[Reembolso]:
    """Reembolsos de la empresa. Un cajero o encargado ve solo los de su sucursal; el administrador, todos."""
    consulta = (
        db.query(Reembolso)
        .options(joinedload(Reembolso.cliente), joinedload(Reembolso.sucursal))
        .filter(Reembolso.empresa_id == usuario.empresa_id)
    )
    if usuario.rol in ("cajero", "encargado_sucursal"):
        if usuario.sucursal_id is None:
            return []
        consulta = consulta.filter(Reembolso.sucursal_id == usuario.sucursal_id)
    if estado:
        consulta = consulta.filter(Reembolso.estado == estado)
    return consulta.order_by(Reembolso.creado_en.desc(), Reembolso.id.desc()).all()


def procesar_reembolso(db: Session, usuario: Usuario, reserva_id: int | None = None, venta_id: int | None = None,
                       request=None) -> Reembolso:
    """El personal ya le transfirió el dinero al cliente: el reembolso queda `reembolsado` y el pedido `reembolsada`.

    Funciona aunque el cliente no haya pedido el reembolso ni subido su QR (p. ej. se lo devuelven en efectivo): en ese caso
    se crea el reembolso en este momento.
    """
    origen = _buscar_origen(db, usuario.empresa_id, reserva_id, venta_id, bloquear=True)
    if usuario.rol in ("cajero", "encargado_sucursal") and origen.sucursal_id != usuario.sucursal_id:
        raise HTTPException(status_code=404, detail="Pedido no encontrado")  # el de otra sucursal no es suyo
    _validar_reembolsable(origen)
    reembolso = _reembolso_de(db, reserva_id, venta_id) or _crear_reembolso(db, usuario.empresa_id, origen)
    reembolso.estado = "reembolsado"
    reembolso.procesado_por_id = usuario.id
    reembolso.procesado_en = datetime.now(timezone.utc)
    origen.estado = ESTADO_REEMBOLSADA
    bitacora.registrar(
        db, "reembolso.procesar",
        f"Reembolso #{reembolso.id} de {reembolso.origen} #{origen.id} por ${reembolso.monto}",
        usuario=usuario, request=request,
    )
    db.commit()
    db.refresh(reembolso)
    return reembolso


def reembolso_pendiente_de(db: Session, empresa_id: int, origen) -> Reembolso:
    """El reembolso del pedido cancelado [origen] (reserva o venta): el que ya existe o uno nuevo, pendiente.

    Lo usa el rechazo de un pago QR (se cancela la venta y el cliente tiene que recibir su dinero). NO confirma la transacción.
    """
    es_reserva = isinstance(origen, Reserva)
    return _reembolso_de(db, origen.id if es_reserva else None, None if es_reserva else origen.id) or _crear_reembolso(db, empresa_id, origen)
