"""Modelos de transferencias de stock entre sucursales (CU19).

Una transferencia recorre una máquina de estados (ver service.TRANSICIONES):
solicitada → en_transito → recibida, con salidas a rechazada o cancelada.
"""
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.shared.db.session import Base


class Transferencia(Base):
    __tablename__ = "transferencias"

    id = Column(Integer, primary_key=True, index=True)
    empresa_id = Column(Integer, ForeignKey("empresas.id"), nullable=False, index=True)
    sucursal_origen_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    sucursal_destino_id = Column(Integer, ForeignKey("sucursales.id"), nullable=False)
    estado = Column(String(20), nullable=False, default="solicitada", index=True)
    motivo = Column(String(255), nullable=True)
    # Motivo del rechazo o diferencia entre lo enviado y lo recibido (CU19 6a y 8a).
    observacion = Column(String(500), nullable=True)
    solicitado_por_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())
    actualizado_en = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    sucursal_origen = relationship("Sucursal", foreign_keys=[sucursal_origen_id])
    sucursal_destino = relationship("Sucursal", foreign_keys=[sucursal_destino_id])
    solicitado_por = relationship("Usuario")
    items = relationship("TransferenciaItem", back_populates="transferencia", cascade="all, delete-orphan")
    historial = relationship(
        "TransferenciaHistorial",
        back_populates="transferencia",
        cascade="all, delete-orphan",
        order_by="TransferenciaHistorial.id",
    )

    @property
    def nombre_origen(self) -> str:
        return self.sucursal_origen.nombre if self.sucursal_origen else ""

    @property
    def nombre_destino(self) -> str:
        return self.sucursal_destino.nombre if self.sucursal_destino else ""

    @property
    def nombre_solicitante(self) -> str:
        return self.solicitado_por.nombre if self.solicitado_por else ""

    @property
    def total_unidades(self) -> int:
        return sum(item.cantidad for item in self.items)


class TransferenciaItem(Base):
    __tablename__ = "transferencia_items"

    id = Column(Integer, primary_key=True, index=True)
    transferencia_id = Column(Integer, ForeignKey("transferencias.id"), nullable=False, index=True)
    # Registro de inventario de la sucursal de origen (producto + talla + color).
    inventario_origen_id = Column(Integer, ForeignKey("inventario.id"), nullable=False)
    cantidad = Column(Integer, nullable=False)
    cantidad_recibida = Column(Integer, nullable=True)  # se completa al confirmar la recepción

    transferencia = relationship("Transferencia", back_populates="items")
    inventario_origen = relationship("Inventario")

    @property
    def producto_id(self) -> int:
        return self.inventario_origen.producto_id

    @property
    def nombre_producto(self) -> str:
        return self.inventario_origen.nombre_producto

    @property
    def nombre_talla(self) -> str | None:
        return self.inventario_origen.nombre_talla

    @property
    def nombre_color(self) -> str | None:
        return self.inventario_origen.nombre_color


class TransferenciaHistorial(Base):
    __tablename__ = "transferencia_historial"

    id = Column(Integer, primary_key=True, index=True)
    transferencia_id = Column(Integer, ForeignKey("transferencias.id"), nullable=False, index=True)
    estado_anterior = Column(String(20), nullable=True)
    estado_nuevo = Column(String(20), nullable=False)
    usuario_id = Column(Integer, ForeignKey("usuarios.id"), nullable=False)
    comentario = Column(String(255), nullable=True)
    creado_en = Column(DateTime(timezone=True), server_default=func.now())

    transferencia = relationship("Transferencia", back_populates="historial")
    usuario = relationship("Usuario")

    @property
    def nombre_usuario(self) -> str:
        return self.usuario.nombre if self.usuario else ""
