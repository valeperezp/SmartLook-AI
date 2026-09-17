"""Lógica de negocio del módulo ia (CU20 — analizar preferencias, CU06 — generar recomendaciones).

Motor basado en reglas: analiza el historial de reservas del cliente (categoría,
temporada, colección de los productos que reservó) y puntúa el catálogo activo
según esas coincidencias. Si el cliente no tiene historial, recomienda lo más
popular entre todos los clientes. Pensado para poder swappearse más adelante por
una llamada a un LLM externo sin tocar el router (ver `ai_api_key` en config).
"""
from collections import Counter

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.modules.catalogo.models import Categoria, Coleccion, Producto, Temporada
from app.modules.inventario.models import Inventario
from app.modules.reservas.models import Reserva, ReservaItem


def _historial_cliente(db: Session, cliente_id: int) -> list[ReservaItem]:
    """Items reservados por el cliente (incluye canceladas: igual reflejan interés)."""
    return (
        db.query(ReservaItem)
        .join(Reserva, Reserva.id == ReservaItem.reserva_id)
        .options(joinedload(ReservaItem.producto))
        .filter(Reserva.cliente_id == cliente_id)
        .all()
    )


def analizar_preferencias(db: Session, cliente_id: int) -> dict:
    """CU20: deriva el perfil de preferencias del cliente a partir de su historial de reservas."""
    historial = _historial_cliente(db, cliente_id)

    if not historial:
        return {"tiene_historial": False, "total_reservas_analizadas": 0, "preferencias": []}

    categoria_peso: Counter = Counter()
    temporada_peso: Counter = Counter()
    coleccion_peso: Counter = Counter()

    for item in historial:
        producto = item.producto
        if not producto:
            continue
        if producto.categoria_id:
            categoria_peso[producto.categoria_id] += item.cantidad
        if producto.temporada_id:
            temporada_peso[producto.temporada_id] += item.cantidad
        if producto.coleccion_id:
            coleccion_peso[producto.coleccion_id] += item.cantidad

    preferencias = []
    for categoria_id, peso in categoria_peso.most_common(3):
        nombre = db.query(Categoria.nombre).filter(Categoria.id == categoria_id).scalar()
        if nombre:
            preferencias.append({"tipo": "categoria", "nombre": nombre, "peso": peso})
    for temporada_id, peso in temporada_peso.most_common(2):
        nombre = db.query(Temporada.nombre).filter(Temporada.id == temporada_id).scalar()
        if nombre:
            preferencias.append({"tipo": "temporada", "nombre": nombre, "peso": peso})
    for coleccion_id, peso in coleccion_peso.most_common(2):
        nombre = db.query(Coleccion.nombre).filter(Coleccion.id == coleccion_id).scalar()
        if nombre:
            preferencias.append({"tipo": "coleccion", "nombre": nombre, "peso": peso})

    preferencias.sort(key=lambda p: p["peso"], reverse=True)

    return {
        "tiene_historial": True,
        "total_reservas_analizadas": len(historial),
        "preferencias": preferencias,
    }


def _popularidad_global(db: Session) -> Counter:
    """Cantidad de unidades reservadas por producto, en todos los clientes (para desempate/fallback)."""
    filas = (
        db.query(ReservaItem.producto_id, func.coalesce(func.sum(ReservaItem.cantidad), 0))
        .join(Reserva, Reserva.id == ReservaItem.reserva_id)
        .filter(Reserva.estado != "cancelada")
        .group_by(ReservaItem.producto_id)
        .all()
    )
    return Counter({producto_id: int(total) for producto_id, total in filas})


def generar_recomendaciones(db: Session, cliente_id: int, limit: int = 8) -> list[dict]:
    """CU06: genera hasta `limit` recomendaciones de productos para el cliente."""
    historial = _historial_cliente(db, cliente_id)

    categoria_peso: Counter = Counter()
    temporada_peso: Counter = Counter()
    coleccion_peso: Counter = Counter()
    ya_reservados: set[int] = set()

    for item in historial:
        producto = item.producto
        if not producto:
            continue
        ya_reservados.add(producto.id)
        if producto.categoria_id:
            categoria_peso[producto.categoria_id] += item.cantidad
        if producto.temporada_id:
            temporada_peso[producto.temporada_id] += item.cantidad
        if producto.coleccion_id:
            coleccion_peso[producto.coleccion_id] += item.cantidad

    # Solo se recomiendan productos activos con stock disponible en alguna sucursal.
    productos_con_stock = {
        pid
        for (pid,) in db.query(Inventario.producto_id)
        .filter(Inventario.activo.is_(True), Inventario.cantidad_disponible > 0)
        .distinct()
        .all()
    }

    candidatos = (
        db.query(Producto)
        .options(joinedload(Producto.categoria))
        .filter(Producto.activo.is_(True), Producto.id.in_(productos_con_stock))
        .all()
    ) if productos_con_stock else []

    popularidad = _popularidad_global(db)

    resultados = []
    for producto in candidatos:
        if producto.id in ya_reservados:
            continue

        puntaje = 0
        motivo = None
        if producto.categoria_id in categoria_peso:
            puntaje += categoria_peso[producto.categoria_id] * 3
            motivo = f"Porque sueles reservar productos de {producto.categoria.nombre}" if producto.categoria else None
        if producto.temporada_id in temporada_peso:
            puntaje += temporada_peso[producto.temporada_id] * 2
            motivo = motivo or "Va con la temporada de tus reservas anteriores"
        if producto.coleccion_id in coleccion_peso:
            puntaje += coleccion_peso[producto.coleccion_id] * 2
            motivo = motivo or "De una colección que ya reservaste antes"

        # Pequeño empuje por popularidad general (no domina el puntaje de afinidad personal).
        puntaje += min(popularidad.get(producto.id, 0), 5)

        if not motivo:
            motivo = "Producto popular entre otros clientes"

        resultados.append({
            "producto_id": producto.id,
            "nombre_producto": producto.nombre,
            "precio": float(producto.precio),
            "nombre_categoria": producto.categoria.nombre if producto.categoria else None,
            "modelo_ar_url": producto.modelo_ar_url,
            "motivo": motivo,
            "puntaje": puntaje,
        })

    resultados.sort(key=lambda r: r["puntaje"], reverse=True)
    return resultados[:limit]
