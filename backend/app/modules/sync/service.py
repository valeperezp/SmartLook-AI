"""Lógica de la sincronización de operaciones offline de la app móvil.

Tipos que recibe (cada uno en su lista del lote):
- `operaciones`: VENTA_CONTADO (cajero) y RESERVA_CLIENTE (cliente).
- `devoluciones`: cambios/devoluciones de una venta de contado ya sincronizada.
- `movimientos_puntos`: puntos de fidelización otorgados o restados.
- `cierres_caja`: cierre de un turno de caja (exige que sus ventas ya estén sincronizadas).

Reglas comunes:
- Cada elemento se procesa en su PROPIA transacción: un conflicto en uno no afecta a los demás.
- Idempotencia: el `uuid` de la app se guarda en `sync_operaciones` junto con lo creado, en la misma transacción. Si el
  uuid ya existe se devuelve el resultado guardado (ok con el mismo id_servidor, o el mismo conflicto).
- Multi-empresa: todo se valida contra la empresa del usuario autenticado (token); algo de otra empresa se trata como
  si no existiera.
- Resultado `conflict`: no puede aplicarse (sin stock, prenda ajena, sin permiso...). Resultado `pendiente`: todavía no
  se puede decidir porque falta algo por sincronizar (la venta original de una devolución, las ventas de un cierre): no
  se registra nada y la app lo reintenta. Un error inesperado NO es conflicto: sube como 500 y la app reintenta.
"""
from collections import defaultdict
from datetime import datetime, timezone
from decimal import Decimal
from typing import Callable

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.modules.bitacora import service as bitacora
from app.modules.catalogo.models import Producto
from app.modules.fidelizacion import service as fidelizacion
from app.modules.inventario.models import MovimientoInventario
from app.modules.reservas import schemas as reservas_schemas
from app.modules.reservas import service as reservas_service
from app.modules.sucursales.models import Sucursal
from app.modules.sync import schemas
from app.modules.sync.models import (
    Devolucion,
    DevolucionItem,
    MovimientoPuntos,
    PuntosCliente,
    SyncOperacion,
    TurnoCaja,
)
from app.modules.usuarios.models import Usuario
from app.modules.ventas import schemas as ventas_schemas
from app.modules.ventas import service as ventas_service
from app.modules.ventas.models import Venta, VentaItem

TIPO_VENTA = "VENTA_CONTADO"
TIPO_RESERVA = "RESERVA_CLIENTE"
TIPO_DEVOLUCION = "DEVOLUCION"
TIPO_CIERRE = "CIERRE_CAJA"
ROLES_VENTA = ("cajero", "administrador", "encargado_sucursal")
ROLES_RESERVA = ("cliente",)


class ConflictoSync(Exception):
    """La operación no puede aplicarse (el mensaje se devuelve a la app)."""


class AplazarSync(Exception):
    """Todavía no se puede decidir (falta algo por sincronizar): no se registra nada y la app reintenta."""


class VentaEnConflicto(Exception):
    """Venta offline sin stock suficiente: se guardó SIN descontar stock, a la espera de que un encargado la resuelva (CU13)."""

    def __init__(self, venta_id: int, mensaje: str):
        super().__init__(mensaje)
        self.venta_id = venta_id
        self.mensaje = mensaje


def _recortar(mensaje: str) -> str:
    return mensaje[:255]


def _dinero(centavos: int | None) -> Decimal:
    return Decimal(centavos or 0) / 100


def _resultado(registro: SyncOperacion) -> schemas.ResultadoItem:
    if registro.estado == "ok":
        return schemas.ResultadoItem(uuid=registro.uuid, status="ok", id_servidor=registro.entidad_id, entidad=registro.entidad)
    if registro.estado == "en_conflicto":
        return schemas.ResultadoItem(uuid=registro.uuid, status="en_conflicto", id_servidor=registro.entidad_id,
                                     entidad=registro.entidad, message=registro.mensaje)
    return schemas.ResultadoItem(uuid=registro.uuid, status="conflict", message=registro.mensaje)


def _existente(db: Session, empresa_id: int, uuid: str) -> SyncOperacion | None:
    return db.query(SyncOperacion).filter(SyncOperacion.empresa_id == empresa_id, SyncOperacion.uuid == uuid).first()


def _fecha_local(texto: str | None) -> datetime | None:
    """Fecha en que ocurrió la operación en el dispositivo (nunca en el futuro). None si no viene o no se entiende."""
    if not texto:
        return None
    try:
        fecha = datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError:
        return None
    if fecha.tzinfo is None:
        fecha = fecha.replace(tzinfo=timezone.utc)
    return min(fecha, datetime.now(timezone.utc))


def _validar_permiso_caja(usuario: Usuario, sucursal_id: int) -> None:
    if usuario.rol not in ROLES_VENTA:
        raise ConflictoSync("Tu rol no puede registrar esta operación de caja")
    if usuario.rol == "cajero" and usuario.sucursal_id != sucursal_id:
        raise ConflictoSync("El cajero solo puede operar en su sucursal asignada")


def _validar_sucursal(db: Session, empresa_id: int, sucursal_id: int) -> None:
    if db.query(Sucursal.id).filter(Sucursal.id == sucursal_id, Sucursal.empresa_id == empresa_id).first() is None:
        raise ConflictoSync("Sucursal no encontrada en tu empresa")


def _validar_productos(db: Session, empresa_id: int, producto_ids) -> None:
    for pid in set(producto_ids):
        if db.query(Producto.id).filter(Producto.id == pid, Producto.empresa_id == empresa_id).first() is None:
            raise ConflictoSync(f"Producto {pid} no encontrado en tu empresa")


# ---------------------------------------------------------------------------------------------------------------
# Flujo idempotente común
# ---------------------------------------------------------------------------------------------------------------

def _registrar_conflicto(db: Session, usuario: Usuario, uuid: str, tipo_operacion: str, mensaje: str) -> schemas.ResultadoItem:
    registro = SyncOperacion(
        empresa_id=usuario.empresa_id, uuid=uuid, tipo_operacion=tipo_operacion[:30],
        estado="conflict", mensaje=_recortar(mensaje), usuario_id=usuario.id,
    )
    db.add(registro)
    try:
        db.commit()
    except IntegrityError:  # otro request con el mismo uuid se adelantó: vale su resultado
        db.rollback()
        previo = _existente(db, usuario.empresa_id, uuid)
        if previo is not None:
            return _resultado(previo)
        raise
    return _resultado(registro)


def _procesar(db: Session, usuario: Usuario, uuid: str, tipo_operacion: str,
              aplicar: Callable[[], tuple[str, int]], reintento: bool = True) -> schemas.ResultadoItem:
    """Aplica una operación una sola vez. `aplicar()` hace los cambios SIN confirmar y devuelve (entidad, id)."""
    previo = _existente(db, usuario.empresa_id, uuid)
    if previo is not None:
        return _resultado(previo)  # idempotencia: no se duplica nada

    try:
        entidad, entidad_id = aplicar()
        registro = SyncOperacion(
            empresa_id=usuario.empresa_id, uuid=uuid, tipo_operacion=tipo_operacion[:30],
            entidad=entidad, entidad_id=entidad_id, estado="ok", usuario_id=usuario.id,
        )
        db.add(registro)
        db.commit()  # lo aplicado + stock + registro de idempotencia: todo o nada
        return _resultado(registro)
    except VentaEnConflicto as e:
        # La venta (sin descontar stock) ya está en la sesión: se confirma junto con el registro de idempotencia
        registro = SyncOperacion(
            empresa_id=usuario.empresa_id, uuid=uuid, tipo_operacion=tipo_operacion[:30], entidad="venta",
            entidad_id=e.venta_id, estado="en_conflicto", mensaje=_recortar(e.mensaje), usuario_id=usuario.id,
        )
        db.add(registro)
        bitacora.registrar(db, "sync.venta_en_conflicto", f"Venta {e.venta_id} en conflicto: {e.mensaje}", usuario=usuario)
        db.commit()
        return _resultado(registro)
    except ConflictoSync as e:
        db.rollback()
        return _registrar_conflicto(db, usuario, uuid, tipo_operacion, str(e))
    except HTTPException as e:  # las reglas de ventas/reservas (sin stock, sin inventario...) responden así
        db.rollback()
        return _registrar_conflicto(db, usuario, uuid, tipo_operacion, str(e.detail))
    except AplazarSync as e:
        db.rollback()
        return schemas.ResultadoItem(uuid=uuid, status="pendiente", message=_recortar(str(e)))
    except IntegrityError:
        db.rollback()
        previo = _existente(db, usuario.empresa_id, uuid)  # carrera con otro request con el mismo uuid
        if previo is not None:
            return _resultado(previo)
        if reintento:  # p. ej. dos movimientos de puntos creando a la vez el saldo del mismo cliente
            return _procesar(db, usuario, uuid, tipo_operacion, aplicar, reintento=False)
        raise
    except Exception:
        db.rollback()
        raise


def _origen(db: Session, empresa_id: int, uuid: str | None) -> SyncOperacion | None:
    """Registro de una operación ya recibida (sirve para ubicar la venta original, el origen de unos puntos...)."""
    return _existente(db, empresa_id, uuid) if uuid else None


# ---------------------------------------------------------------------------------------------------------------
# Ventas y reservas
# ---------------------------------------------------------------------------------------------------------------

def _validar_empresa_operacion(db: Session, empresa_id: int, op: schemas.OperacionSync) -> None:
    """Sucursal y productos deben ser de la empresa del usuario (si no, es como si no existieran)."""
    _validar_sucursal(db, empresa_id, op.sucursal_id)
    if not op.items:
        raise ConflictoSync("La operación no tiene ítems")
    for item in op.items:
        if item.cantidad < 1:
            raise ConflictoSync(f"Cantidad inválida para el producto {item.producto_id}")
    _validar_productos(db, empresa_id, [i.producto_id for i in op.items])


def _aplicar_descuento_por_puntos(db: Session, empresa_id: int, puntos: int, venta: Venta) -> None:
    """CU17: la venta se hizo offline con un canje de [puntos]: el total del servidor lleva el mismo descuento.

    Solo baja el total; los puntos se restan con el movimiento PUNTOS_RESTADOS ("canje") que sube la app.
    """
    if puntos <= 0:
        return
    descuento = puntos * fidelizacion.valor_punto_centavos(db, empresa_id)
    bruto = fidelizacion.a_centavos(venta.total)
    if descuento > bruto:
        raise ConflictoSync("El descuento por puntos supera el total de la venta")
    venta.total = (bruto - descuento) / 100


def _cliente_de_la_empresa(db: Session, empresa_id: int, cliente_id: int | None) -> int | None:
    """Cliente (para puntos) de una venta de contado: solo si existe y es de la misma empresa; si no, venta anónima."""
    if cliente_id is None:
        return None
    ok = db.query(Usuario.id).filter(Usuario.id == cliente_id, Usuario.empresa_id == empresa_id, Usuario.rol == "cliente").first()
    return cliente_id if ok else None


def _aplicar_operacion(db: Session, usuario: Usuario, op: schemas.OperacionSync) -> tuple[str, int]:
    """Crea la venta o la reserva SIN confirmar la transacción. Devuelve (entidad, id)."""
    empresa_id = usuario.empresa_id
    if op.tipo_operacion == TIPO_VENTA:
        if usuario.rol not in ROLES_VENTA:
            raise ConflictoSync("Tu rol no puede registrar ventas")
        if usuario.rol == "cajero" and usuario.sucursal_id != op.sucursal_id:
            raise ConflictoSync("El cajero solo puede vender en su sucursal asignada")
        _validar_empresa_operacion(db, empresa_id, op)
        data = ventas_schemas.VentaPresencialCreate(
            sucursal_id=op.sucursal_id,
            cliente_id=_cliente_de_la_empresa(db, empresa_id, op.cliente_id),
            items=[ventas_schemas.VentaItemCreate(producto_id=i.producto_id, talla_id=i.talla_id, color_id=i.color_id, cantidad=i.cantidad) for i in op.items],
        )
        fecha = _fecha_local(op.fecha)
        # CU13: sin stock suficiente la venta NO se rechaza: se guarda `en_conflicto` (sin descontar nada) y la resuelve
        # un encargado desde la web. Otros problemas (producto ajeno, sin permiso...) siguen siendo conflicto definitivo.
        faltantes = ventas_service.detectar_faltantes_de_stock(db, op.sucursal_id, data.items)
        if faltantes:
            venta = ventas_service.crear_venta_en_conflicto(db, data, cajero_id=usuario.id)
            _aplicar_descuento_por_puntos(db, empresa_id, op.puntos_canjeados, venta)
            if fecha is not None:
                venta.creada_en = fecha
            raise VentaEnConflicto(venta.id, "; ".join(faltantes))
        venta = ventas_service.crear_venta_presencial(db, data, cajero_id=usuario.id, commit=False)
        _aplicar_descuento_por_puntos(db, empresa_id, op.puntos_canjeados, venta)
        if fecha is not None:
            venta.creada_en = fecha
        return "venta", venta.id

    if op.tipo_operacion == TIPO_RESERVA:
        if usuario.rol not in ROLES_RESERVA:
            raise ConflictoSync("Solo un cliente puede registrar reservas")
        if op.cliente_id is not None and op.cliente_id != usuario.id:
            raise ConflictoSync("La reserva es de otro cliente")
        _validar_empresa_operacion(db, empresa_id, op)
        data = reservas_schemas.ReservaCreate(
            sucursal_id=op.sucursal_id,
            items=[reservas_schemas.ReservaItemCreate(producto_id=i.producto_id, talla_id=i.talla_id, color_id=i.color_id, cantidad=i.cantidad) for i in op.items],
        )
        reserva = reservas_service.crear_reserva(db, data, cliente_id=usuario.id, commit=False)
        fecha = _fecha_local(op.fecha)
        if fecha is not None:
            reserva.creada_en = fecha
        return "reserva", reserva.id

    raise ConflictoSync(f"Tipo de operación no soportado: {op.tipo_operacion}")


# ---------------------------------------------------------------------------------------------------------------
# Cambios y devoluciones
# ---------------------------------------------------------------------------------------------------------------

def _agrupar(items: list[schemas.ItemDevolucionSync]) -> dict[tuple, dict]:
    """Suma las cantidades de la misma prenda (producto + talla + color)."""
    grupos: dict[tuple, dict] = {}
    for i in items:
        if i.cantidad < 1:
            raise ConflictoSync(f"Cantidad inválida para el producto {i.producto_id}")
        clave = (i.producto_id, i.talla_id or 0, i.color_id or 0)
        if clave in grupos:
            grupos[clave]["cantidad"] += i.cantidad
        else:
            grupos[clave] = {"producto_id": i.producto_id, "talla_id": i.talla_id, "color_id": i.color_id, "cantidad": i.cantidad}
    return grupos


def _aplicar_devolucion(db: Session, usuario: Usuario, d: schemas.DevolucionSync) -> tuple[str, int]:
    empresa_id = usuario.empresa_id
    _validar_permiso_caja(usuario, d.sucursal_id)
    _validar_sucursal(db, empresa_id, d.sucursal_id)
    if not d.items_devueltos:
        raise ConflictoSync("Hay que devolver al menos una prenda")

    # Venta original: se ubica por el uuid con el que la app la sincronizó (así nunca es de otra empresa)
    origen = _origen(db, empresa_id, d.venta_uuid)
    if origen is None:
        raise AplazarSync("La venta original aún no está sincronizada")
    if origen.estado == "en_conflicto":
        raise AplazarSync("La venta original está en conflicto de stock: espera a que el encargado la resuelva")
    if origen.estado != "ok" or origen.entidad != "venta":
        raise ConflictoSync("La venta original fue rechazada por el servidor")
    venta = db.query(Venta).filter(Venta.id == origen.entidad_id).first()
    if venta is None or venta.sucursal_id != d.sucursal_id:
        raise ConflictoSync("La venta original no pertenece a esta sucursal")

    devueltos = _agrupar(d.items_devueltos)
    nuevos = _agrupar(d.items_nuevos)

    # Lo que se puede devolver: lo vendido menos lo ya devuelto en cambios/devoluciones anteriores de esa venta
    vendidas: dict[tuple, dict] = {}
    for vi in venta.items:
        clave = (vi.producto_id, vi.talla_id or 0, vi.color_id or 0)
        linea = vendidas.setdefault(clave, {"item": vi, "cantidad": 0})
        linea["cantidad"] += vi.cantidad
    ya_devueltas: dict[tuple, int] = defaultdict(int)
    previas = (
        db.query(DevolucionItem.producto_id, DevolucionItem.talla_id, DevolucionItem.color_id, func.sum(DevolucionItem.cantidad))
        .join(Devolucion, Devolucion.id == DevolucionItem.devolucion_id)
        .filter(Devolucion.venta_id == venta.id, DevolucionItem.tipo_item == "devuelto")
        .group_by(DevolucionItem.producto_id, DevolucionItem.talla_id, DevolucionItem.color_id)
        .all()
    )
    for pid, tid, cid, cant in previas:
        ya_devueltas[(pid, tid or 0, cid or 0)] += int(cant)
    for clave, g in devueltos.items():
        linea = vendidas.get(clave)
        if linea is None:
            raise ConflictoSync("Una de las prendas no pertenece a la venta original")
        maximo = linea["cantidad"] - ya_devueltas.get(clave, 0)
        if g["cantidad"] > maximo:
            raise ConflictoSync(f"De '{linea['item'].nombre_producto}' solo se pueden devolver {max(maximo, 0)} unidad(es)")
    _validar_productos(db, empresa_id, [g["producto_id"] for g in nuevos.values()])

    dev = Devolucion(
        empresa_id=empresa_id, uuid=d.uuid, venta_id=venta.id, sucursal_id=d.sucursal_id, cajero_id=usuario.id,
        tipo=(d.tipo or "cambio")[:30], motivo=(d.motivo or None) and d.motivo[:255], turno_uuid=d.turno_uuid,
        fecha=_fecha_local(d.fecha),
    )
    db.add(dev)
    db.flush()

    # 1) Lo devuelto vuelve a la estantería (primero, así un cambio por la misma prenda no choca con stock 0)
    total_devuelto = Decimal(0)
    for clave in sorted(devueltos):
        g, vi = devueltos[clave], vendidas[clave]["item"]
        inventario = ventas_service._buscar_inventario(db, vi.producto_id, venta.sucursal_id, vi.talla_id, vi.color_id)
        if inventario is None:
            raise ConflictoSync(f"No hay inventario de '{vi.nombre_producto}' en esta sucursal")
        inventario.cantidad_disponible += g["cantidad"]
        inventario.cantidad_vendida = max(0, inventario.cantidad_vendida - g["cantidad"])
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
            raise ConflictoSync(f"No hay inventario de '{producto.nombre}' en esta sucursal")
        if inventario.cantidad_disponible < g["cantidad"]:
            raise ConflictoSync(f"Stock insuficiente para '{producto.nombre}'. Disponible: {inventario.cantidad_disponible}, solicitado: {g['cantidad']}")
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
    return "devolucion", dev.id


# ---------------------------------------------------------------------------------------------------------------
# Puntos de fidelización
# ---------------------------------------------------------------------------------------------------------------

def _aplicar_puntos(db: Session, usuario: Usuario, m: schemas.MovimientoPuntosSync) -> tuple[str, int]:
    empresa_id = usuario.empresa_id
    if usuario.rol not in ROLES_VENTA:
        raise ConflictoSync("Tu rol no puede registrar puntos")
    if m.tipo_operacion not in schemas.TIPOS_PUNTOS:
        raise ConflictoSync(f"Tipo de movimiento de puntos no soportado: {m.tipo_operacion}")
    if m.cantidad < 1:
        raise ConflictoSync("La cantidad de puntos debe ser positiva")
    cliente = db.query(Usuario).filter(Usuario.id == m.cliente_id, Usuario.empresa_id == empresa_id, Usuario.rol == "cliente").first()
    if cliente is None:
        raise ConflictoSync("Cliente no encontrado en tu empresa")

    # Los puntos salen de una venta o de una devolución: si esa operación aún no llegó, se espera; si se rechazó, también esto
    if m.operacion_uuid:
        origen = _origen(db, empresa_id, m.operacion_uuid)
        if origen is None:
            raise AplazarSync("La operación de origen aún no está sincronizada")
        if origen.estado == "en_conflicto":
            raise AplazarSync("La operación de origen está en conflicto de stock: espera a que el encargado la resuelva")
        if origen.estado != "ok":
            raise ConflictoSync("La operación de origen fue rechazada por el servidor")

    saldo = db.query(PuntosCliente).filter(PuntosCliente.cliente_id == cliente.id).with_for_update().first()
    if saldo is None:
        saldo = PuntosCliente(empresa_id=empresa_id, cliente_id=cliente.id, saldo=0)
        db.add(saldo)
        db.flush()
    if m.motivo == "canje" and m.tipo_operacion == "PUNTOS_RESTADOS" and saldo.saldo < m.cantidad:
        # CU17: un canje no puede gastar más de lo que el cliente tiene (el resto de restas sí se recorta a 0)
        raise ConflictoSync(f"Puntos insuficientes para el canje: el cliente tiene {saldo.saldo} y se canjearon {m.cantidad}")
    delta = m.cantidad if m.tipo_operacion == "PUNTOS_OTORGADOS" else -m.cantidad
    saldo.saldo = max(saldo.saldo + delta, 0)  # el saldo nunca baja de 0, igual que en la app

    mov = MovimientoPuntos(
        empresa_id=empresa_id, uuid=m.uuid, cliente_id=cliente.id, tipo_operacion=m.tipo_operacion, cantidad=m.cantidad,
        operacion_uuid=m.operacion_uuid, venta_uuid=m.venta_uuid, fecha=_fecha_local(m.fecha),
    )
    db.add(mov)
    db.flush()
    return "movimiento_puntos", mov.id


# ---------------------------------------------------------------------------------------------------------------
# Cierre de caja
# ---------------------------------------------------------------------------------------------------------------

def _aplicar_cierre(db: Session, usuario: Usuario, c: schemas.CierreCajaSync) -> tuple[str, int]:
    empresa_id = usuario.empresa_id
    _validar_permiso_caja(usuario, c.sucursal_id)
    _validar_sucursal(db, empresa_id, c.sucursal_id)

    # El cierre solo vale si todo lo del turno ya está en el servidor
    faltan = 0
    venta_ids: list[int] = []
    for uuid in c.operaciones:
        origen = _origen(db, empresa_id, uuid)
        if origen is None or origen.estado == "en_conflicto":  # en conflicto: su total aún no es definitivo
            faltan += 1
        elif origen.estado != "ok" or origen.entidad != "venta":
            raise ConflictoSync("Una venta del turno fue rechazada por el servidor")
        else:
            venta_ids.append(origen.entidad_id)
    for uuid in c.devoluciones:
        origen = _origen(db, empresa_id, uuid)
        if origen is None:
            faltan += 1
        elif origen.estado != "ok":
            raise ConflictoSync("Un cambio o devolución del turno fue rechazado por el servidor")
    if faltan:
        raise AplazarSync(f"Faltan {faltan} operaciones del turno por sincronizar o resolver")

    total_ventas = Decimal(0)
    if venta_ids:
        ventas = db.query(Venta).filter(Venta.id.in_(venta_ids)).all()
        if any(v.sucursal_id != c.sucursal_id for v in ventas):
            raise ConflictoSync("Hay ventas del turno de otra sucursal")
        total_ventas = sum((Decimal(str(v.total)) for v in ventas), Decimal(0))

    turno = TurnoCaja(
        empresa_id=empresa_id, uuid=c.uuid, sucursal_id=c.sucursal_id, cajero_id=usuario.id,
        fecha_apertura=_fecha_local(c.fecha_apertura), fecha_cierre=_fecha_local(c.fecha_cierre),
        monto_inicial=_dinero(c.monto_inicial_centavos), monto_esperado=_dinero(c.monto_esperado_centavos),
        monto_real=_dinero(c.monto_real_centavos), diferencia=_dinero(c.diferencia_centavos),
        devoluciones_neto=_dinero(c.devoluciones_neto_centavos), num_ventas=len(venta_ids), total_ventas_servidor=total_ventas,
    )
    db.add(turno)
    db.flush()
    return "turno_caja", turno.id


# ---------------------------------------------------------------------------------------------------------------

def sincronizar_lote(db: Session, usuario: Usuario, lote: schemas.LoteSyncRequest, request=None) -> schemas.LoteSyncResponse:
    if usuario.empresa_id is None:
        raise HTTPException(status_code=403, detail="Esta acción requiere pertenecer a una empresa")

    # (uuid, tipo de operación, función que lo aplica). Orden: ventas/reservas, devoluciones, puntos y cierres,
    # como la app (cada cosa necesita lo anterior ya guardado).
    trabajos: list[tuple[str, str, Callable[[], tuple[str, int]]]] = []
    for op in lote.operaciones:
        trabajos.append((op.uuid, op.tipo_operacion, lambda op=op: _aplicar_operacion(db, usuario, op)))
    for d in lote.devoluciones:
        trabajos.append((d.uuid, TIPO_DEVOLUCION, lambda d=d: _aplicar_devolucion(db, usuario, d)))
    for m in lote.movimientos_puntos:
        trabajos.append((m.uuid, m.tipo_operacion, lambda m=m: _aplicar_puntos(db, usuario, m)))
    for c in lote.cierres_caja:
        trabajos.append((c.uuid, TIPO_CIERRE, lambda c=c: _aplicar_cierre(db, usuario, c)))

    resultados: list[schemas.ResultadoItem] = []
    vistos: dict[str, schemas.ResultadoItem] = {}
    for uuid, tipo, aplicar in trabajos:
        if uuid not in vistos:  # el mismo uuid repetido dentro del lote se procesa una sola vez
            vistos[uuid] = _procesar(db, usuario, uuid, tipo, aplicar)
        resultados.append(vistos[uuid])

    if resultados:
        ok = sum(1 for r in resultados if r.status == "ok")
        conflictos = sum(1 for r in resultados if r.status == "conflict")
        bitacora.registrar(
            db, "sync.lote",
            f"Sincronización móvil: {ok} ok, {conflictos} en conflicto, {len(resultados) - ok - conflictos} en espera de {len(resultados)}",
            usuario=usuario, request=request,
        )
        db.commit()
    return schemas.LoteSyncResponse(resultados=resultados)


# ---------------------------------------------------------------------------------------------------------------
# Resolución manual de conflictos de stock (CU13): lo hace un encargado (de su sucursal) o un administrador
# ---------------------------------------------------------------------------------------------------------------

def listar_conflictos(db: Session, usuario: Usuario, sucursal_id: int | None = None) -> list[schemas.ConflictoOut]:
    """Ventas `en_conflicto` de la empresa. Un encargado ve solo las de su sucursal; el administrador, todas (o una)."""
    consulta = (
        db.query(Venta)
        .join(Sucursal, Venta.sucursal_id == Sucursal.id)
        .options(
            joinedload(Venta.items).joinedload(VentaItem.producto),
            joinedload(Venta.items).joinedload(VentaItem.talla),
            joinedload(Venta.items).joinedload(VentaItem.color),
            joinedload(Venta.sucursal),
            joinedload(Venta.cajero),
        )
        .filter(Venta.estado == "en_conflicto", Sucursal.empresa_id == usuario.empresa_id)
    )
    if usuario.rol == "encargado_sucursal":
        if usuario.sucursal_id is None:
            return []
        consulta = consulta.filter(Venta.sucursal_id == usuario.sucursal_id)
    elif sucursal_id is not None:
        consulta = consulta.filter(Venta.sucursal_id == sucursal_id)
    ventas = consulta.order_by(Venta.creada_en, Venta.id).all()

    registros = {}
    if ventas:
        for r in db.query(SyncOperacion).filter(
            SyncOperacion.empresa_id == usuario.empresa_id, SyncOperacion.entidad == "venta",
            SyncOperacion.estado == "en_conflicto", SyncOperacion.entidad_id.in_([v.id for v in ventas]),
        ):
            registros[r.entidad_id] = r

    salida = []
    for v in ventas:
        r = registros.get(v.id)
        salida.append(schemas.ConflictoOut(
            venta_id=v.id, uuid=r.uuid if r else None, sucursal_id=v.sucursal_id, nombre_sucursal=v.nombre_sucursal,
            cajero_id=v.cajero_id, nombre_cajero=v.nombre_cajero, total=float(v.total),
            creada_en=v.creada_en.isoformat() if v.creada_en else None, motivo=r.mensaje if r else None,
            items=[schemas.ConflictoItemOut(
                producto_id=i.producto_id, nombre_producto=i.producto.nombre if i.producto else f"Producto {i.producto_id}",
                talla_id=i.talla_id, nombre_talla=i.talla.nombre if i.talla else None,
                color_id=i.color_id, nombre_color=i.color.nombre if i.color else None,
                cantidad=i.cantidad, precio_unitario=float(i.precio_unitario),
            ) for i in v.items],
        ))
    return salida


def _descontar_pedido(db: Session, usuario: Usuario, sucursal_id: int, pedido: dict[tuple, int], motivo: str) -> None:
    """Descuenta del inventario lo pedido (aunque deje el stock negativo) y registra el movimiento de cada variante."""
    for (producto_id, talla_id, color_id), cantidad in pedido.items():
        inventario = ventas_service._buscar_inventario(db, producto_id, sucursal_id, talla_id, color_id)
        if inventario is None:
            producto = db.get(Producto, producto_id)
            nombre = ventas_service.nombre_variante(db, producto, talla_id, color_id) if producto else f"producto {producto_id}"
            raise HTTPException(status_code=400, detail=f"No hay inventario de {nombre} en esta sucursal: usa Ajustar variante")
        inventario.cantidad_disponible -= cantidad
        inventario.cantidad_vendida += cantidad
        db.add(MovimientoInventario(inventario_id=inventario.id, tipo="venta", cantidad=cantidad, motivo=motivo, usuario_id=usuario.id))
    db.flush()


def resolver_conflicto(db: Session, usuario: Usuario, venta_id: int, data: schemas.ResolverConflictoRequest,
                       request=None) -> schemas.ResolverConflictoResponse:
    """Resuelve una venta `en_conflicto`: ANULAR (no descuenta), AJUSTAR (otras prendas, con stock) o FORZAR (descuenta aunque quede negativo)."""
    venta = (
        db.query(Venta)
        .join(Sucursal, Venta.sucursal_id == Sucursal.id)
        .filter(Venta.id == venta_id, Sucursal.empresa_id == usuario.empresa_id)
        .with_for_update(of=Venta)
        .first()
    )
    # Una venta de otra empresa (o de otra sucursal, para un encargado) se trata como si no existiera
    if venta is None or (usuario.rol == "encargado_sucursal" and venta.sucursal_id != usuario.sucursal_id):
        raise HTTPException(status_code=404, detail="Venta no encontrada")
    if venta.estado != "en_conflicto":
        raise HTTPException(status_code=409, detail="Esta venta ya no está en conflicto")

    registro = db.query(SyncOperacion).filter(
        SyncOperacion.empresa_id == usuario.empresa_id, SyncOperacion.entidad == "venta", SyncOperacion.entidad_id == venta.id,
    ).first()
    nota = f": {data.motivo.strip()}" if data.motivo and data.motivo.strip() else ""

    try:
        if data.accion == "ANULAR":
            venta.estado = "anulada"  # no se descontó nada al guardarla, así que no hay nada que devolver
            if registro:
                registro.estado, registro.mensaje = "conflict", _recortar(f"Venta anulada por el encargado{nota}")
        elif data.accion == "FORZAR":
            _descontar_pedido(db, usuario, venta.sucursal_id, ventas_service.agrupar_por_variante(venta.items),
                              "Venta forzada por el encargado (el stock puede quedar negativo)")
            venta.estado = "completada"
            if registro:
                registro.estado, registro.mensaje = "ok", _recortar(f"Forzada por el encargado{nota}")
        else:  # AJUSTAR
            if not data.items:
                raise HTTPException(status_code=400, detail="Indica las prendas del ajuste")
            for pid in {i.producto_id for i in data.items}:
                if db.query(Producto.id).filter(Producto.id == pid, Producto.empresa_id == usuario.empresa_id).first() is None:
                    raise HTTPException(status_code=400, detail=f"Producto {pid} no encontrado en tu empresa")
            faltantes = ventas_service.detectar_faltantes_de_stock(db, venta.sucursal_id, data.items)
            if faltantes:
                raise HTTPException(status_code=400, detail="; ".join(faltantes))
            for item in list(venta.items):
                db.delete(item)
            db.flush()
            total = 0.0
            for it in data.items:
                precio = float(db.get(Producto, it.producto_id).precio)
                db.add(VentaItem(venta_id=venta.id, producto_id=it.producto_id, talla_id=it.talla_id, color_id=it.color_id,
                                 cantidad=it.cantidad, precio_unitario=precio))
                total += precio * it.cantidad
            venta.total = total
            _descontar_pedido(db, usuario, venta.sucursal_id, ventas_service.agrupar_por_variante(data.items),
                              "Venta ajustada por el encargado")
            venta.estado = "completada"
            if registro:
                registro.estado, registro.mensaje = "ok", _recortar(f"Ajustada por el encargado{nota}")

        bitacora.registrar(db, "sync.conflicto_resuelto", f"Venta {venta.id}: {data.accion}{nota}", usuario=usuario, request=request)
        db.commit()
    except HTTPException:
        db.rollback()
        raise
    return schemas.ResolverConflictoResponse(venta_id=venta.id, accion=data.accion, estado=venta.estado, total=float(venta.total))
