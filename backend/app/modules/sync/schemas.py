"""Esquemas Pydantic del módulo Sync. Contrato con la app móvil (`SyncService`).

La app manda UN lote por tipo, con la lista en su propia clave: `operaciones` (ventas y reservas), `devoluciones`,
`movimientos_puntos` y `cierres_caja`. Cada elemento lleva `uuid` (id local = clave de idempotencia).
"""
from typing import Literal

from pydantic import BaseModel, Field

TIPOS_PUNTOS = ("PUNTOS_OTORGADOS", "PUNTOS_RESTADOS")


class ItemSync(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int
    precio_unitario_centavos: int | None = None  # informativo: el servidor cobra con el precio vigente


class OperacionSync(BaseModel):
    uuid: str = Field(..., min_length=1, max_length=64)  # id local de la app = clave de idempotencia
    tipo_operacion: str  # VENTA_CONTADO | RESERVA_CLIENTE
    sucursal_id: int
    cajero_id: int | None = None
    cliente_id: int | None = None
    fecha: str | None = None  # ISO 8601: cuándo ocurrió en el dispositivo
    total_centavos: int | None = None
    items: list[ItemSync] = []
    # CU17: puntos que el cliente canjeó en esta venta offline. El servidor aplica el descuento al total (valor del punto de
    # su empresa); los puntos en sí se restan con el movimiento PUNTOS_RESTADOS (motivo "canje") que sube la app.
    puntos_canjeados: int = Field(0, ge=0)


# ---------- Devolución / cambio ----------
class ItemDevolucionSync(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int
    precio_centavos: int | None = None  # informativo: lo devuelto se reembolsa al precio de la venta original


class DevolucionSync(BaseModel):
    uuid: str = Field(..., min_length=1, max_length=64)  # = devolucion_id local
    venta_uuid: str = Field(..., min_length=1, max_length=64)  # uuid de la venta original (ya sincronizada)
    tipo: str = "cambio"  # cambio | devolucion
    motivo: str | None = None
    fecha: str | None = None
    turno_uuid: str | None = None
    cajero_id: int | None = None
    sucursal_id: int
    total_devuelto_centavos: int | None = None
    total_nuevo_centavos: int | None = None
    diferencia_centavos: int | None = None
    items_devueltos: list[ItemDevolucionSync] = []
    items_nuevos: list[ItemDevolucionSync] = []


# ---------- Puntos de fidelización ----------
class MovimientoPuntosSync(BaseModel):
    uuid: str = Field(..., min_length=1, max_length=64)  # = movimiento_id local
    tipo_operacion: str  # PUNTOS_OTORGADOS (suma) | PUNTOS_RESTADOS (resta)
    cliente_id: int
    cantidad: int
    operacion_uuid: str | None = None  # venta o devolución de origen
    venta_uuid: str | None = None
    fecha: str | None = None
    motivo: str | None = None  # "canje": puntos usados como descuento (se exige saldo suficiente; no se recorta a 0)


# ---------- Cierre de caja ----------
class CierreCajaSync(BaseModel):
    uuid: str = Field(..., min_length=1, max_length=64)  # = turno_uuid
    sucursal_id: int
    cajero_id: int | None = None
    fecha_apertura: str | None = None
    fecha_cierre: str | None = None
    monto_inicial_centavos: int = 0
    monto_esperado_centavos: int = 0
    monto_real_centavos: int = 0
    diferencia_centavos: int = 0
    operaciones: list[str] = []  # uuids de las ventas del turno: deben estar ya sincronizadas
    devoluciones: list[str] = []  # uuids de los cambios/devoluciones del turno
    devoluciones_neto_centavos: int = 0


class LoteSyncRequest(BaseModel):
    enviado_en: str | None = None
    operaciones: list[OperacionSync] = []
    devoluciones: list[DevolucionSync] = []
    movimientos_puntos: list[MovimientoPuntosSync] = []
    cierres_caja: list[CierreCajaSync] = []


class ResultadoItem(BaseModel):
    uuid: str
    # ok: aplicado (o ya estaba aplicado) · conflict: no puede aplicarse, la app lo rechaza ·
    # pendiente: todavía no se puede decidir (falta algo por sincronizar), la app lo reintenta más tarde
    # en_conflicto: la venta SÍ se guardó (con su id_servidor) pero sin descontar stock, por falta de stock: un encargado la resuelve
    status: Literal["ok", "conflict", "pendiente", "en_conflicto"]
    id_servidor: int | None = None  # id de lo creado en el servidor (solo con status ok)
    entidad: Literal["venta", "reserva", "devolucion", "movimiento_puntos", "turno_caja"] | None = None
    message: str | None = None  # motivo del conflicto o de la espera


class LoteSyncResponse(BaseModel):
    resultados: list[ResultadoItem]


# ---------- Resolución manual de conflictos (CU13) ----------
class ItemAjusteSync(BaseModel):
    producto_id: int
    talla_id: int | None = None
    color_id: int | None = None
    cantidad: int = Field(..., ge=1)


class ResolverConflictoRequest(BaseModel):
    accion: Literal["ANULAR", "AJUSTAR", "FORZAR"]
    items: list[ItemAjusteSync] = []  # solo AJUSTAR: el nuevo listado de prendas (p. ej. otra talla)
    motivo: str | None = Field(default=None, max_length=200)  # nota opcional del encargado


class ConflictoItemOut(BaseModel):
    producto_id: int
    nombre_producto: str
    talla_id: int | None = None
    nombre_talla: str | None = None
    color_id: int | None = None
    nombre_color: str | None = None
    cantidad: int
    precio_unitario: float


class ConflictoOut(BaseModel):
    venta_id: int
    uuid: str | None = None  # id con el que el dispositivo mandó la venta
    sucursal_id: int
    nombre_sucursal: str | None = None
    cajero_id: int | None = None
    nombre_cajero: str | None = None
    total: float
    creada_en: str | None = None
    motivo: str | None = None
    items: list[ConflictoItemOut] = []


class ResolverConflictoResponse(BaseModel):
    venta_id: int
    accion: str
    estado: str  # completada | anulada
    total: float
