"""Modelo de datos del módulo Sync (sincronización de la app móvil offline).

`SyncOperacion` guarda el resultado de cada operación recibida de un dispositivo, identificada por el `uuid` que
generó la app. Sirve de clave de idempotencia: si el mismo `uuid` llega otra vez (reintento tras un corte de red)
se devuelve el resultado ya guardado en lugar de crear otra venta o reserva.

`ventas` y `reservas` no tienen columna para ese uuid y no se altera su tabla (la base es compartida): el vínculo
vive aquí, en una tabla nueva que `create_all` crea sola al arrancar.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, Numeric, String, UniqueConstraint
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class SyncOperacion(Base):
    __tablename__ = "sync_operaciones"
    __table_args__ = (UniqueConstraint("empresa_id", "uuid", name="ux_sync_operaciones_empresa_uuid"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    uuid = Column(String(64), nullable=False)
    tipo_operacion = Column(String(30), nullable=False)
    entidad = Column(String(20), nullable=True)  # venta | reserva | devolucion | movimiento_puntos | turno_caja
    entidad_id = Column(Integer, nullable=True)  # id de lo creado en el servidor = id_servidor
    estado = Column(String(20), nullable=False)  # ok | conflict
    mensaje = Column(String(255), nullable=True)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())


# ---------------------------------------------------------------------------------------------------------------
# Devoluciones, puntos de fidelización y turnos de caja: el backend no los tenía; son lo mínimo para poder recibir
# lo que la app registra sin conexión. Todos llevan empresa_id y el uuid de la app (único por empresa).
# ---------------------------------------------------------------------------------------------------------------
class Devolucion(Base):
    """Cambio o devolución de una venta de contado. Lo devuelto vuelve al inventario; lo nuevo se descuenta."""

    __tablename__ = "devoluciones"
    __table_args__ = (UniqueConstraint("empresa_id", "uuid", name="ux_devoluciones_empresa_uuid"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    uuid = Column(String(64), nullable=False)
    venta_id = Column(Integer, ForeignKey("ventas.id"), nullable=False, index=True)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    cajero_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    tipo = Column(String(30), nullable=False)  # cambio | devolucion
    motivo = Column(String(255), nullable=True)
    turno_uuid = Column(String(64), nullable=True)
    total_devuelto = Column(Numeric(10, 2), nullable=False, default=0)
    total_nuevo = Column(Numeric(10, 2), nullable=False, default=0)
    fecha = Column(DateTime(timezone=True), nullable=True)  # cuándo ocurrió en el dispositivo
    creada_en = Column(DateTime(timezone=True), server_default=func.now())

    items = relationship("DevolucionItem", back_populates="devolucion", cascade="all, delete-orphan")


class DevolucionItem(Base):
    __tablename__ = "devolucion_items"

    id = Column(Integer, primary_key=True, index=True)
    devolucion_id = Column(Integer, ForeignKey("devoluciones.id"), nullable=False, index=True)
    tipo_item = Column(String(10), nullable=False)  # devuelto | nuevo
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    talla_id = Column(Integer, ForeignKey("tallas.id"), nullable=True)
    color_id = Column(Integer, ForeignKey("colores.id"), nullable=True)
    cantidad = Column(Integer, nullable=False)
    precio_unitario = Column(Numeric(10, 2), nullable=False)

    devolucion = relationship("Devolucion", back_populates="items")


class PuntosCliente(Base):
    """Saldo de puntos de fidelización de un cliente (nunca baja de 0)."""

    __tablename__ = "puntos_clientes"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, unique=True)
    saldo = Column(Integer, nullable=False, default=0)
    actualizado_en = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class MovimientoPuntos(Base):
    __tablename__ = "movimientos_puntos"
    __table_args__ = (UniqueConstraint("empresa_id", "uuid", name="ux_movimientos_puntos_empresa_uuid"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    uuid = Column(String(64), nullable=False)
    cliente_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False, index=True)
    tipo_operacion = Column(String(30), nullable=False)  # PUNTOS_OTORGADOS | PUNTOS_RESTADOS
    cantidad = Column(Integer, nullable=False)  # siempre positiva; el tipo dice si suma o resta
    operacion_uuid = Column(String(64), nullable=True)  # venta o devolución que lo originó
    venta_uuid = Column(String(64), nullable=True)
    fecha = Column(DateTime(timezone=True), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())


class TurnoCaja(Base):
    """Cierre de caja de un cajero (apertura con monto inicial, arqueo al cierre)."""

    __tablename__ = "turnos_caja"
    __table_args__ = (UniqueConstraint("empresa_id", "uuid", name="ux_turnos_caja_empresa_uuid"),)

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    uuid = Column(String(64), nullable=False)
    sucursal_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    cajero_id = Column(Integer, ForeignKey("usuarios.id"), nullable=True)
    fecha_apertura = Column(DateTime(timezone=True), nullable=True)
    fecha_cierre = Column(DateTime(timezone=True), nullable=True)
    monto_inicial = Column(Numeric(12, 2), nullable=False, default=0)
    monto_esperado = Column(Numeric(12, 2), nullable=False, default=0)  # lo que calculó la app
    monto_real = Column(Numeric(12, 2), nullable=False, default=0)  # lo contado por el cajero
    diferencia = Column(Numeric(12, 2), nullable=False, default=0)  # real - esperado (negativa = faltante)
    devoluciones_neto = Column(Numeric(12, 2), nullable=False, default=0)
    num_ventas = Column(Integer, nullable=False, default=0)
    total_ventas_servidor = Column(Numeric(12, 2), nullable=False, default=0)  # suma de las ventas del turno en el servidor
    creado_en = Column(DateTime(timezone=True), server_default=func.now())
