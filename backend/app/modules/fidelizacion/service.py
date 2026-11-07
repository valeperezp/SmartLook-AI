"""Lógica de la fidelización (CU17): regla de puntos por empresa, saldo y canje de puntos como descuento.

Reglas:
- 1 punto vale `valor_punto_centavos` de descuento (regla de la EMPRESA; por defecto 1000 = 10 Bs).
- El canje resta los puntos del saldo y baja el total de la venta, en la MISMA transacción que la venta.
- No se puede canjear más de lo que se tiene, ni un descuento mayor al total de la venta.
- Si una venta online con canje se cancela, los puntos canjeados se devuelven al saldo (una sola vez).
"""
from datetime import datetime, timezone
from decimal import ROUND_HALF_UP, Decimal

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.fidelizacion.models import ConfiguracionFidelizacion
from app.modules.sync.models import MovimientoPuntos, PuntosCliente
from app.modules.usuarios.models import Usuario

VALOR_PUNTO_POR_DEFECTO = 1000


def valor_punto_centavos(db: Session, empresa_id: int | None) -> int:
    """Cuánto vale un punto en la empresa (la regla vive en el backend, no en las apps)."""
    if empresa_id is not None:
        config = db.get(ConfiguracionFidelizacion, empresa_id)
        if config is not None and config.valor_punto_centavos > 0:
            return config.valor_punto_centavos
    return VALOR_PUNTO_POR_DEFECTO


def guardar_regla(db: Session, empresa_id: int, valor: int) -> int:
    config = db.get(ConfiguracionFidelizacion, empresa_id)
    if config is None:
        db.add(ConfiguracionFidelizacion(empresa_id=empresa_id, valor_punto_centavos=valor))
    else:
        config.valor_punto_centavos = valor
    db.commit()
    return valor


def saldo_de(db: Session, cliente_id: int) -> int:
    fila = db.query(PuntosCliente.saldo).filter(PuntosCliente.cliente_id == cliente_id).first()
    return fila[0] if fila else 0


def a_centavos(monto) -> int:
    """Un monto en moneda (19.99) a centavos enteros, sin el error binario de float."""
    return int((Decimal(str(monto)) * 100).to_integral_value(ROUND_HALF_UP))


def _cliente_de_la_empresa(db: Session, cliente_id: int | None, empresa_id: int) -> Usuario:
    if cliente_id is None:
        raise HTTPException(status_code=400, detail="Para canjear puntos la venta debe tener un cliente registrado")
    cliente = db.query(Usuario).filter(Usuario.id == cliente_id, Usuario.rol == "cliente", Usuario.empresa_id == empresa_id).first()
    if cliente is None:
        raise HTTPException(status_code=400, detail="Cliente no encontrado en tu empresa")
    return cliente


def mis_puntos(db: Session, cliente: Usuario):
    saldo = saldo_de(db, cliente.id)
    valor = valor_punto_centavos(db, cliente.empresa_id)
    return {"cliente_id": cliente.id, "saldo": saldo, "valor_punto_centavos": valor, "valor_saldo_centavos": saldo * valor}


def puntos_de_cliente(db: Session, empresa_id: int, cliente_id: int):
    """Saldo de un cliente de la misma empresa (lo consulta el cajero al cobrar)."""
    return mis_puntos(db, _cliente_de_la_empresa_404(db, cliente_id, empresa_id))


def _cliente_de_la_empresa_404(db: Session, cliente_id: int, empresa_id: int) -> Usuario:
    cliente = db.query(Usuario).filter(Usuario.id == cliente_id, Usuario.rol == "cliente", Usuario.empresa_id == empresa_id).first()
    if cliente is None:
        raise HTTPException(status_code=404, detail="Cliente no encontrado")
    return cliente


def aplicar_canje(db: Session, *, empresa_id: int, cliente_id: int | None, puntos: int, total, venta_id: int) -> float:
    """Canjea [puntos] como descuento de una venta de [total]. Devuelve el descuento (en moneda).

    Resta los puntos del saldo (con el saldo bloqueado: dos canjes a la vez no pueden pasar de lo que hay) y deja el
    movimiento PUNTOS_RESTADOS. NO confirma la transacción: lo hace quien crea la venta. Cualquier regla rota lanza
    HTTP 400 y, como nada se confirmó, la venta no se guarda.
    """
    if puntos <= 0:
        return 0.0
    _cliente_de_la_empresa(db, cliente_id, empresa_id)

    valor = valor_punto_centavos(db, empresa_id)
    descuento = puntos * valor
    if descuento > a_centavos(total):
        raise HTTPException(
            status_code=400,
            detail=f"El descuento por puntos ({descuento / 100:.2f}) no puede ser mayor al total de la compra ({a_centavos(total) / 100:.2f})",
        )

    saldo = db.query(PuntosCliente).filter(PuntosCliente.cliente_id == cliente_id).with_for_update().first()
    disponible = saldo.saldo if saldo else 0
    if puntos > disponible:
        raise HTTPException(status_code=400, detail=f"Puntos insuficientes: tienes {disponible} y quieres canjear {puntos}")

    saldo.saldo = disponible - puntos
    db.add(MovimientoPuntos(
        empresa_id=empresa_id, uuid=f"canje-venta-{venta_id}", cliente_id=cliente_id, tipo_operacion="PUNTOS_RESTADOS",
        cantidad=puntos, operacion_uuid=f"venta-{venta_id}", venta_uuid=f"venta-{venta_id}", fecha=datetime.now(timezone.utc),
    ))
    db.flush()
    return descuento / 100


def devolver_canje_de_venta(db: Session, venta) -> None:
    """La venta se canceló: los puntos que se canjearon en ella vuelven al saldo (una sola vez). No confirma."""
    canje = db.query(MovimientoPuntos).filter(MovimientoPuntos.uuid == f"canje-venta-{venta.id}").first()
    if canje is None:
        return
    reintegro_uuid = f"reintegro-venta-{venta.id}"
    if db.query(MovimientoPuntos.id).filter(MovimientoPuntos.uuid == reintegro_uuid).first() is not None:
        return  # ya se devolvieron
    saldo = db.query(PuntosCliente).filter(PuntosCliente.cliente_id == canje.cliente_id).with_for_update().first()
    if saldo is None:
        saldo = PuntosCliente(empresa_id=canje.empresa_id, cliente_id=canje.cliente_id, saldo=0)
        db.add(saldo)
    saldo.saldo += canje.cantidad
    db.add(MovimientoPuntos(
        empresa_id=canje.empresa_id, uuid=reintegro_uuid, cliente_id=canje.cliente_id, tipo_operacion="PUNTOS_OTORGADOS",
        cantidad=canje.cantidad, operacion_uuid=f"venta-{venta.id}", venta_uuid=f"venta-{venta.id}", fecha=datetime.now(timezone.utc),
    ))
    db.flush()
