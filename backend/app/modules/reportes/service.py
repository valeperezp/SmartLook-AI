"""Lógica de negocio del módulo reportes.

- CU15 — Consultar dashboard analítico: ventas, reservas e inventario.
- CU14 — Solicitar reporte generativo: `contexto_reporte` arma los datos reales
  que la IA usa para redactar el reporte y que se exportan a PDF/Excel.

Multi-empresa: ventas y reservas pertenecen a una sucursal, y la sucursal a una
empresa; todas las consultas filtran por Sucursal.empresa_id.
"""
from datetime import date, datetime, timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Categoria, Producto
from app.modules.inventario import service as inventario_service
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.db.tenant import asegurar_de_empresa

ESTADO_VENTA_VALIDA = "completada"


def sucursal_efectiva(usuario: Usuario, sucursal_id: int | None, db: Session | None = None) -> int | None:
    """Un encargado solo puede ver reportes de su propia sucursal; el admin puede ver todo o filtrar.

    Centralizado acá (no solo en el router HTTP) porque el asistente de IA de reportes
    también necesita aplicar exactamente esta misma regla de alcance por rol.
    """
    if usuario.rol == "encargado_sucursal":
        if not usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El encargado de sucursal no tiene una sucursal asignada.",
            )
        if sucursal_id is not None and sucursal_id != usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para ver reportes de otra sucursal.",
            )
        return usuario.sucursal_id
    if db is not None:
        # El admin puede filtrar por cualquier sucursal, pero solo de su empresa.
        asegurar_de_empresa(db, Sucursal, sucursal_id, usuario.empresa_id, "Sucursal")
    return sucursal_id


def nombre_sucursal(db: Session, sucursal_id: int | None, empresa_id: int | None = None) -> str:
    if sucursal_id is None:
        return "Todas las sucursales"
    query = db.query(Sucursal).filter(Sucursal.id == sucursal_id)
    if empresa_id is not None:
        query = query.filter(Sucursal.empresa_id == empresa_id)
    sucursal = query.first()
    return sucursal.nombre if sucursal else "Todas las sucursales"


def _desde(dias: int) -> datetime:
    """Inicio del período: hace `dias` días a las 00:00 hora de Bolivia (incluye hoy)."""
    hoy = datetime.now(ZONA_HORARIA_LOCAL).date()
    inicio = hoy - timedelta(days=dias - 1)
    return datetime(inicio.year, inicio.month, inicio.day, tzinfo=ZONA_HORARIA_LOCAL)


def _fecha_local(columna):
    """Fecha calendario en Bolivia de una columna timestamptz (para agrupar por día)."""
    return func.date(func.timezone("America/La_Paz", columna))


def _serie_completa(filas: dict[date, dict], dias: int, vacio: dict) -> list[dict]:
    """Completa con ceros los días sin movimiento para que los gráficos no salten fechas."""
    hoy = datetime.now(ZONA_HORARIA_LOCAL).date()
    serie = []
    for i in range(dias - 1, -1, -1):
        dia = hoy - timedelta(days=i)
        serie.append({"fecha": dia.isoformat(), **filas.get(dia, vacio)})
    return serie


def _f(valor) -> float:
    return float(valor or 0) if not isinstance(valor, Decimal) else float(valor)


# ======================================================================
# Ventas (CU15)
# ======================================================================

def _ventas(db: Session, empresa_id: int, sucursal_id: int | None, dias: int | None):
    query = (
        db.query(Venta)
        .join(Sucursal, Sucursal.id == Venta.sucursal_id)
        .filter(Sucursal.empresa_id == empresa_id, Venta.estado == ESTADO_VENTA_VALIDA)
    )
    if sucursal_id is not None:
        query = query.filter(Venta.sucursal_id == sucursal_id)
    if dias is not None:
        query = query.filter(Venta.creada_en >= _desde(dias))
    return query


def resumen_ventas(db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 30) -> dict:
    ventas = _ventas(db, empresa_id, sucursal_id, dias)
    cantidad, ingresos = ventas.with_entities(func.count(Venta.id), func.coalesce(func.sum(Venta.total), 0)).one()
    unidades = (
        ventas.join(VentaItem, VentaItem.venta_id == Venta.id)
        .with_entities(func.coalesce(func.sum(VentaItem.cantidad), 0))
        .scalar()
    )
    # Mismo período inmediatamente anterior, para mostrar la variación.
    anterior_desde = _desde(dias * 2)
    anterior = (
        _ventas(db, empresa_id, sucursal_id, None)
        .filter(Venta.creada_en >= anterior_desde, Venta.creada_en < _desde(dias))
        .with_entities(func.coalesce(func.sum(Venta.total), 0))
        .scalar()
    )
    ingresos_f, anterior_f = _f(ingresos), _f(anterior)
    variacion = round((ingresos_f - anterior_f) / anterior_f * 100, 1) if anterior_f else None
    return {
        "cantidad_ventas": int(cantidad),
        "ingresos": round(ingresos_f, 2),
        "ticket_promedio": round(ingresos_f / cantidad, 2) if cantidad else 0.0,
        "unidades_vendidas": int(unidades or 0),
        "variacion_ingresos_pct": variacion,
    }


def ventas_por_dia(db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 30) -> list[dict]:
    dia = _fecha_local(Venta.creada_en)
    filas = (
        _ventas(db, empresa_id, sucursal_id, dias)
        .with_entities(dia, func.count(Venta.id), func.coalesce(func.sum(Venta.total), 0))
        .group_by(dia)
        .all()
    )
    por_dia = {f: {"cantidad": int(c), "ingresos": round(_f(t), 2)} for f, c, t in filas}
    return _serie_completa(por_dia, dias, {"cantidad": 0, "ingresos": 0.0})


def ventas_por_sucursal(db: Session, empresa_id: int, dias: int = 30) -> list[dict]:
    filas = (
        db.query(
            Sucursal.id,
            Sucursal.nombre,
            func.count(Venta.id),
            func.coalesce(func.sum(Venta.total), 0),
        )
        .outerjoin(
            Venta,
            (Venta.sucursal_id == Sucursal.id)
            & (Venta.estado == ESTADO_VENTA_VALIDA)
            & (Venta.creada_en >= _desde(dias)),
        )
        .filter(Sucursal.empresa_id == empresa_id, Sucursal.activa.is_(True))
        .group_by(Sucursal.id, Sucursal.nombre)
        .order_by(func.coalesce(func.sum(Venta.total), 0).desc())
        .all()
    )
    return [
        {"sucursal_id": sid, "nombre_sucursal": nombre, "cantidad_ventas": int(c), "ingresos": round(_f(t), 2)}
        for sid, nombre, c, t in filas
    ]


def ventas_por_categoria(db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 30) -> list[dict]:
    subtotal = func.sum(VentaItem.cantidad * VentaItem.precio_unitario)
    filas = (
        _ventas(db, empresa_id, sucursal_id, dias)
        .join(VentaItem, VentaItem.venta_id == Venta.id)
        .join(Producto, Producto.id == VentaItem.producto_id)
        .outerjoin(Categoria, Categoria.id == Producto.categoria_id)
        .with_entities(Categoria.nombre, func.sum(VentaItem.cantidad), subtotal)
        .group_by(Categoria.nombre)
        .order_by(subtotal.desc())
        .all()
    )
    return [
        {"categoria": nombre or "Sin categoría", "unidades": int(u), "ingresos": round(_f(t), 2)}
        for nombre, u, t in filas
    ]


def ventas_por_canal(db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 30) -> list[dict]:
    filas = (
        _ventas(db, empresa_id, sucursal_id, dias)
        .with_entities(Venta.canal, func.count(Venta.id), func.coalesce(func.sum(Venta.total), 0))
        .group_by(Venta.canal)
        .all()
    )
    return [{"canal": canal or "presencial", "cantidad": int(c), "ingresos": round(_f(t), 2)} for canal, c, t in filas]


def productos_mas_vendidos(
    db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 30, limit: int = 10
) -> list[dict]:
    unidades = func.sum(VentaItem.cantidad)
    filas = (
        _ventas(db, empresa_id, sucursal_id, dias)
        .join(VentaItem, VentaItem.venta_id == Venta.id)
        .join(Producto, Producto.id == VentaItem.producto_id)
        .outerjoin(Categoria, Categoria.id == Producto.categoria_id)
        .with_entities(
            Producto.id, Producto.nombre, Categoria.nombre, unidades,
            func.sum(VentaItem.cantidad * VentaItem.precio_unitario),
        )
        .group_by(Producto.id, Producto.nombre, Categoria.nombre)
        .order_by(unidades.desc())
        .limit(limit)
        .all()
    )
    return [
        {"producto_id": pid, "nombre_producto": nombre, "nombre_categoria": cat,
         "unidades": int(u), "ingresos": round(_f(t), 2)}
        for pid, nombre, cat, u, t in filas
    ]


# ======================================================================
# Reservas
# ======================================================================

def _reservas(db: Session, empresa_id: int, sucursal_id: int | None):
    query = db.query(Reserva).join(Sucursal, Sucursal.id == Reserva.sucursal_id).filter(Sucursal.empresa_id == empresa_id)
    if sucursal_id is not None:
        query = query.filter(Reserva.sucursal_id == sucursal_id)
    return query


def reservas_por_estado(db: Session, empresa_id: int, sucursal_id: int | None = None) -> list[dict]:
    """Cuenta las reservas agrupadas por estado (global o de una sucursal)."""
    filas = (
        _reservas(db, empresa_id, sucursal_id)
        .with_entities(Reserva.estado, func.count(Reserva.id))
        .group_by(Reserva.estado)
        .all()
    )
    return [{"estado": estado, "cantidad": cantidad} for estado, cantidad in filas]


def reservas_por_sucursal(db: Session, empresa_id: int) -> list[dict]:
    """Cuenta reservas y unidades totales agrupadas por sucursal (solo admin, vista global)."""
    filas = (
        db.query(
            Sucursal.id,
            Sucursal.nombre,
            func.count(func.distinct(Reserva.id)),
            func.coalesce(func.sum(ReservaItem.cantidad), 0),
        )
        .outerjoin(Reserva, Reserva.sucursal_id == Sucursal.id)
        .outerjoin(ReservaItem, ReservaItem.reserva_id == Reserva.id)
        .filter(Sucursal.activa.is_(True), Sucursal.empresa_id == empresa_id)
        .group_by(Sucursal.id, Sucursal.nombre)
        .order_by(Sucursal.nombre)
        .all()
    )
    return [
        {
            "sucursal_id": sucursal_id,
            "nombre_sucursal": nombre,
            "cantidad_reservas": cantidad_reservas,
            "total_unidades": int(total_unidades),
        }
        for sucursal_id, nombre, cantidad_reservas, total_unidades in filas
    ]


def productos_mas_reservados(
    db: Session, empresa_id: int, sucursal_id: int | None = None, limit: int = 10
) -> list[dict]:
    """Ranking de productos por unidades reservadas (excluye reservas canceladas)."""
    query = (
        _reservas(db, empresa_id, sucursal_id)
        .join(ReservaItem, ReservaItem.reserva_id == Reserva.id)
        .join(Producto, Producto.id == ReservaItem.producto_id)
        .outerjoin(Categoria, Categoria.id == Producto.categoria_id)
        .filter(Reserva.estado != "cancelada")
        .with_entities(
            Producto.id,
            Producto.nombre,
            Categoria.nombre,
            func.coalesce(func.sum(ReservaItem.cantidad), 0),
            func.count(func.distinct(ReservaItem.reserva_id)),
        )
    )
    filas = (
        query.group_by(Producto.id, Producto.nombre, Categoria.nombre)
        .order_by(func.coalesce(func.sum(ReservaItem.cantidad), 0).desc())
        .limit(limit)
        .all()
    )
    return [
        {
            "producto_id": producto_id,
            "nombre_producto": nombre,
            "nombre_categoria": nombre_categoria,
            "total_unidades": int(total_unidades),
            "total_reservas": total_reservas,
        }
        for producto_id, nombre, nombre_categoria, total_unidades, total_reservas in filas
    ]


def reservas_por_dia(db: Session, empresa_id: int, sucursal_id: int | None = None, dias: int = 14) -> list[dict]:
    """Serie temporal de reservas creadas en los últimos N días."""
    dia = _fecha_local(Reserva.creada_en)
    filas = (
        _reservas(db, empresa_id, sucursal_id)
        .filter(Reserva.creada_en >= _desde(dias))
        .with_entities(dia, func.count(Reserva.id))
        .group_by(dia)
        .all()
    )
    por_dia = {f: {"cantidad": int(c)} for f, c in filas}
    return _serie_completa(por_dia, dias, {"cantidad": 0})


def resumen_general(db: Session, empresa_id: int, sucursal_id: int | None = None) -> dict:
    """Resumen combinado de reservas + inventario para el dashboard de reportes."""
    total_reservas = _reservas(db, empresa_id, sucursal_id).count()
    total_unidades = int(
        _reservas(db, empresa_id, sucursal_id)
        .join(ReservaItem, ReservaItem.reserva_id == Reserva.id)
        .with_entities(func.coalesce(func.sum(ReservaItem.cantidad), 0))
        .scalar()
        or 0
    )
    inv = inventario_service.resumen_global(db, sucursal_id=sucursal_id, empresa_id=empresa_id)
    return {
        "total_reservas": total_reservas,
        "total_unidades_reservadas": total_unidades,
        "reservas_por_estado": reservas_por_estado(db, empresa_id, sucursal_id=sucursal_id),
        "inventario_disponible": inv["total_disponibles"],
        "inventario_reservado": inv["total_reservados"],
        "productos_stock_bajo": inv["productos_stock_bajo"],
        "productos_agotados": inv["productos_agotados"],
    }


# ======================================================================
# Dashboard (CU15) y contexto para reportes generativos (CU14)
# ======================================================================

def dashboard(db: Session, empresa_id: int, sucursal_id: int | None, dias: int, es_admin: bool) -> dict:
    """Todo lo que muestra el dashboard analítico en una sola respuesta."""
    return {
        "periodo_dias": dias,
        "nombre_sucursal": nombre_sucursal(db, sucursal_id, empresa_id),
        "ventas": resumen_ventas(db, empresa_id, sucursal_id, dias),
        "ventas_por_dia": ventas_por_dia(db, empresa_id, sucursal_id, dias),
        "ventas_por_sucursal": ventas_por_sucursal(db, empresa_id, dias) if es_admin and sucursal_id is None else [],
        "ventas_por_categoria": ventas_por_categoria(db, empresa_id, sucursal_id, dias),
        "ventas_por_canal": ventas_por_canal(db, empresa_id, sucursal_id, dias),
        "top_vendidos": productos_mas_vendidos(db, empresa_id, sucursal_id, dias, limit=8),
        "resumen": resumen_general(db, empresa_id, sucursal_id),
        "reservas_por_dia": reservas_por_dia(db, empresa_id, sucursal_id, dias),
        "top_reservados": productos_mas_reservados(db, empresa_id, sucursal_id, limit=8),
        "alertas_stock": inventario_service.alertas_stock_bajo(db, empresa_id, sucursal_id=sucursal_id)[:10],
    }


def contexto_reporte(db: Session, usuario: Usuario, sucursal_id: int | None, dias: int) -> tuple[dict, str]:
    """Datos reales del período (para la IA y para exportar) y su versión en texto plano.

    La IA solo puede redactar con lo que está acá: así no inventa cifras.
    """
    es_admin = usuario.rol == "administrador"
    efectiva = sucursal_efectiva(usuario, sucursal_id, db)
    datos = dashboard(db, usuario.empresa_id, efectiva, dias, es_admin)
    datos["empresa"] = usuario.empresa_nombre or ""
    v, r = datos["ventas"], datos["resumen"]

    ahora = datetime.now(ZONA_HORARIA_LOCAL)
    lineas = [
        f"Fecha y hora actual: {ahora.strftime('%d/%m/%Y, %H:%M')} (hora de Bolivia)",
        f"Empresa: {datos['empresa']} — alcance: {datos['nombre_sucursal']} — período: últimos {dias} días",
        f"Quién pregunta: {'Administrador' if es_admin else 'Encargado de sucursal'}",
        "",
        "== Ventas del período ==",
        f"Ventas completadas: {v['cantidad_ventas']}",
        f"Ingresos: Bs {v['ingresos']:.2f}",
        f"Ticket promedio: Bs {v['ticket_promedio']:.2f}",
        f"Unidades vendidas: {v['unidades_vendidas']}",
        "Variación de ingresos vs. período anterior: "
        + (f"{v['variacion_ingresos_pct']}%" if v["variacion_ingresos_pct"] is not None else "sin datos del período anterior"),
    ]
    if datos["ventas_por_sucursal"]:
        lineas.append("\n== Ventas por sucursal ==")
        lineas += [f"{s['nombre_sucursal']}: {s['cantidad_ventas']} ventas, Bs {s['ingresos']:.2f}" for s in datos["ventas_por_sucursal"]]
    if datos["ventas_por_categoria"]:
        lineas.append("\n== Ventas por categoría ==")
        lineas += [f"{c['categoria']}: {c['unidades']} unidades, Bs {c['ingresos']:.2f}" for c in datos["ventas_por_categoria"]]
    if datos["ventas_por_canal"]:
        lineas.append("\n== Ventas por canal ==")
        lineas += [f"{c['canal']}: {c['cantidad']} ventas, Bs {c['ingresos']:.2f}" for c in datos["ventas_por_canal"]]
    if datos["top_vendidos"]:
        lineas.append("\n== Productos más vendidos ==")
        lineas += [f"{p['nombre_producto']}: {p['unidades']} unidades, Bs {p['ingresos']:.2f}" for p in datos["top_vendidos"]]
    dias_con_ventas = [d for d in datos["ventas_por_dia"] if d["cantidad"]]
    if dias_con_ventas:
        lineas.append("\n== Ventas por día (solo días con ventas) ==")
        lineas += [f"{d['fecha']}: {d['cantidad']} ventas, Bs {d['ingresos']:.2f}" for d in dias_con_ventas]
    lineas += [
        "\n== Reservas e inventario (estado actual) ==",
        f"Reservas totales: {r['total_reservas']} ({r['total_unidades_reservadas']} unidades)",
        f"Inventario disponible: {r['inventario_disponible']} unidades; reservado: {r['inventario_reservado']}",
        f"Prendas con stock bajo: {r['productos_stock_bajo']}; agotadas: {r['productos_agotados']}",
    ]
    if r["reservas_por_estado"]:
        lineas.append("Reservas por estado: " + ", ".join(f"{e['estado']} {e['cantidad']}" for e in r["reservas_por_estado"]))
    if datos["alertas_stock"]:
        lineas.append("\n== Alertas de stock ==")
        lineas += [f"{a['nombre_producto']} en {a['nombre_sucursal']}: {a['cantidad_disponible']} (mínimo {a['stock_minimo']})"
                   for a in datos["alertas_stock"]]
    return datos, "\n".join(lineas)
