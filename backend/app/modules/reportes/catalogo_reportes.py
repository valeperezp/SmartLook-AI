"""Catálogo cerrado de reportes permitidos (CU14).

La IA solo elige un tipo de esta lista y sus filtros; nunca escribe consultas. Cada tipo es
una consulta parametrizada que SIEMPRE filtra por la empresa del usuario (Sucursal.empresa_id).
"""
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Callable

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.modules.analitica_ml.models import ModeloML
from app.modules.catalogo.models import Categoria, Producto
from app.modules.inventario.models import Inventario
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL


@dataclass
class Filtros:
    """Parámetros ya validados: ids de la empresa y fechas reales."""
    empresa_id: int
    fecha_inicio: date | None = None
    fecha_fin: date | None = None
    sucursal_ids: list[int] = field(default_factory=list)
    categoria_ids: list[int] = field(default_factory=list)
    producto_ids: list[int] = field(default_factory=list)
    limite: int = 10


@dataclass
class TipoReporte:
    id: str
    titulo: str
    descripcion: str
    usa_fechas: bool
    grafico: str  # barras | lineas | torta
    columnas: list[dict]
    ejecutar: Callable[[Session, Filtros], list[dict]]
    usa_categorias: bool = True
    usa_productos: bool = False
    usa_limite: bool = False
    ejemplo: str = ""
    # Cada fila trae la clave "sucursal": la web dibuja un gráfico por sucursal (comparables).
    agrupa_por_sucursal: bool = False
    # Funcionalidad del plan que además exige (p. ej. las estimaciones usan el modelo de ML, CU15).
    requiere: str | None = None


def _rango(f: Filtros) -> tuple[datetime, datetime]:
    """Inicio y fin del rango en hora de Bolivia (fin inclusivo: hasta las 23:59:59)."""
    return (
        datetime.combine(f.fecha_inicio, time.min, tzinfo=ZONA_HORARIA_LOCAL),
        datetime.combine(f.fecha_fin + timedelta(days=1), time.min, tzinfo=ZONA_HORARIA_LOCAL),
    )


def _ventas(db: Session, f: Filtros, *entidades):
    desde, hasta = _rango(f)
    q = (
        db.query(*entidades)
        .select_from(Venta)
        .join(Sucursal, Sucursal.id == Venta.sucursal_id)
        .filter(
            Sucursal.empresa_id == f.empresa_id,
            Venta.estado == "completada",
            Venta.creada_en >= desde,
            Venta.creada_en < hasta,
        )
    )
    if f.sucursal_ids:
        q = q.filter(Venta.sucursal_id.in_(f.sucursal_ids))
    return q


def _con_items(q, f: Filtros):
    """Une ítems y productos solo cuando hace falta (filtro o agrupación por producto/categoría)."""
    q = q.join(VentaItem, VentaItem.venta_id == Venta.id).join(Producto, Producto.id == VentaItem.producto_id)
    if f.categoria_ids:
        q = q.filter(Producto.categoria_id.in_(f.categoria_ids))
    if f.producto_ids:
        q = q.filter(Producto.id.in_(f.producto_ids))
    return q


def _num(valor) -> float:
    return float(valor) if isinstance(valor, Decimal) else float(valor or 0)


_SUBTOTAL = func.sum(VentaItem.cantidad * VentaItem.precio_unitario)


def ventas_por_sucursal(db: Session, f: Filtros) -> list[dict]:
    q = _ventas(db, f, Sucursal.nombre, func.count(func.distinct(Venta.id)), func.sum(VentaItem.cantidad), _SUBTOTAL)
    filas = _con_items(q, f).group_by(Sucursal.nombre).order_by(_SUBTOTAL.desc()).all()
    return [{"etiqueta": n, "ventas": int(c), "unidades": int(u), "ingresos": round(_num(t), 2)} for n, c, u, t in filas]


def ventas_por_categoria(db: Session, f: Filtros) -> list[dict]:
    q = _ventas(db, f, Categoria.nombre, func.sum(VentaItem.cantidad), _SUBTOTAL)
    q = _con_items(q, f).join(Categoria, Categoria.id == Producto.categoria_id)
    filas = q.group_by(Categoria.nombre).order_by(_SUBTOTAL.desc()).all()
    return [{"etiqueta": n, "unidades": int(u), "ingresos": round(_num(t), 2)} for n, u, t in filas]


def ventas_por_producto(db: Session, f: Filtros) -> list[dict]:
    unidades = func.sum(VentaItem.cantidad)
    q = _ventas(db, f, Producto.nombre, unidades, _SUBTOTAL)
    filas = _con_items(q, f).group_by(Producto.nombre).order_by(unidades.desc()).limit(f.limite).all()
    return [{"etiqueta": n, "unidades": int(u), "ingresos": round(_num(t), 2)} for n, u, t in filas]


def ventas_por_dia(db: Session, f: Filtros) -> list[dict]:
    dia = func.date(func.timezone("America/La_Paz", Venta.creada_en))
    if f.categoria_ids or f.producto_ids:
        q = _con_items(_ventas(db, f, dia, func.count(func.distinct(Venta.id)), _SUBTOTAL), f)
    else:
        q = _ventas(db, f, dia, func.count(Venta.id), func.sum(Venta.total))
    por_dia = {d: (int(c), _num(t)) for d, c, t in q.group_by(dia).all()}
    filas, actual = [], f.fecha_inicio
    while actual <= f.fecha_fin:  # días sin ventas en 0, para que la línea no salte
        c, t = por_dia.get(actual, (0, 0.0))
        filas.append({"etiqueta": actual.isoformat(), "ventas": c, "ingresos": round(t, 2)})
        actual += timedelta(days=1)
    return filas


def ventas_por_canal(db: Session, f: Filtros) -> list[dict]:
    filas = (
        _ventas(db, f, Venta.canal, func.count(Venta.id), func.sum(Venta.total))
        .group_by(Venta.canal).order_by(func.sum(Venta.total).desc()).all()
    )
    nombres = {"online": "Online", "presencial": "Presencial"}
    return [{"etiqueta": nombres.get(c, c or "Presencial"), "ventas": int(n), "ingresos": round(_num(t), 2)} for c, n, t in filas]


def mejores_clientes(db: Session, f: Filtros) -> list[dict]:
    monto = func.sum(Venta.total)
    filas = (
        _ventas(db, f, Usuario.nombre, func.count(Venta.id), monto)
        .join(Usuario, Usuario.id == Venta.cliente_id)
        .group_by(Usuario.id, Usuario.nombre).order_by(monto.desc()).limit(f.limite).all()
    )
    return [{"etiqueta": n, "compras": int(c), "monto": round(_num(t), 2)} for n, c, t in filas]


def _inventario(db: Session, f: Filtros, *entidades):
    q = (
        db.query(*entidades)
        .select_from(Inventario)
        .join(Sucursal, Sucursal.id == Inventario.sucursal_id)
        .join(Producto, Producto.id == Inventario.producto_id)
        .filter(Sucursal.empresa_id == f.empresa_id, Inventario.activo.is_(True))
    )
    if f.sucursal_ids:
        q = q.filter(Inventario.sucursal_id.in_(f.sucursal_ids))
    if f.categoria_ids:
        q = q.filter(Producto.categoria_id.in_(f.categoria_ids))
    if f.producto_ids:
        q = q.filter(Producto.id.in_(f.producto_ids))
    return q


def inventario_por_sucursal(db: Session, f: Filtros) -> list[dict]:
    filas = (
        _inventario(db, f, Sucursal.nombre, func.sum(Inventario.cantidad_disponible), func.sum(Inventario.cantidad_reservada))
        .group_by(Sucursal.nombre).order_by(Sucursal.nombre).all()
    )
    return [{"etiqueta": n, "disponible": int(d or 0), "reservado": int(r or 0)} for n, d, r in filas]


def stock_bajo(db: Session, f: Filtros) -> list[dict]:
    filas = (
        _inventario(db, f, Producto.nombre, Sucursal.nombre, Inventario.cantidad_disponible, Inventario.stock_minimo)
        .filter(Inventario.cantidad_disponible <= Inventario.stock_minimo)
        .order_by(Inventario.cantidad_disponible, Producto.nombre).all()
    )
    return [{"etiqueta": f"{p} · {s}", "disponible": int(d), "minimo": int(m)} for p, s, d, m in filas]


def reservas_por_estado(db: Session, f: Filtros) -> list[dict]:
    desde, hasta = _rango(f)
    q = (
        db.query(Reserva.estado, func.count(Reserva.id))
        .join(Sucursal, Sucursal.id == Reserva.sucursal_id)
        .filter(Sucursal.empresa_id == f.empresa_id, Reserva.creada_en >= desde, Reserva.creada_en < hasta)
    )
    if f.sucursal_ids:
        q = q.filter(Reserva.sucursal_id.in_(f.sucursal_ids))
    if f.categoria_ids or f.producto_ids:
        q = q.join(ReservaItem, ReservaItem.reserva_id == Reserva.id).join(Producto, Producto.id == ReservaItem.producto_id)
        if f.categoria_ids:
            q = q.filter(Producto.categoria_id.in_(f.categoria_ids))
        if f.producto_ids:
            q = q.filter(Producto.id.in_(f.producto_ids))
    filas = q.group_by(Reserva.estado).order_by(func.count(Reserva.id).desc()).all()
    return [{"etiqueta": (e or "pendiente").capitalize(), "reservas": int(c)} for e, c in filas]


# ---------------------------------------------------------------- reportes agrupados por sucursal

def sucursales_del_reporte(db: Session, f: Filtros) -> list[tuple[int, str]]:
    """(id, nombre) de las sucursales activas que abarca el reporte (todas las de la empresa o las pedidas)."""
    q = db.query(Sucursal.id, Sucursal.nombre).filter(Sucursal.empresa_id == f.empresa_id, Sucursal.activa.isnot(False))
    if f.sucursal_ids:
        q = q.filter(Sucursal.id.in_(f.sucursal_ids))
    return q.order_by(Sucursal.nombre).all()


def productos_por_sucursal(db: Session, f: Filtros) -> list[dict]:
    """Top N de prendas más vendidas DENTRO de cada sucursal (no un top general filtrado)."""
    unidades = func.sum(VentaItem.cantidad)
    q = _ventas(db, f, Sucursal.nombre, Producto.nombre, unidades, _SUBTOTAL)
    por_sucursal: dict[str, list[dict]] = {}
    for sucursal, producto, u, t in _con_items(q, f).group_by(Sucursal.nombre, Producto.nombre).all():
        por_sucursal.setdefault(sucursal, []).append(
            {"sucursal": sucursal, "etiqueta": producto, "unidades": int(u or 0), "ingresos": round(_num(t), 2)}
        )
    filas: list[dict] = []
    # Primero la sucursal que más vendió; dentro de cada una, el ranking de sus prendas.
    for sucursal in sorted(por_sucursal, key=lambda s: (-sum(x["unidades"] for x in por_sucursal[s]), s)):
        ranking = sorted(por_sucursal[sucursal], key=lambda x: (-x["unidades"], -x["ingresos"], x["etiqueta"]))
        filas.extend(ranking[: f.limite])
    return filas


def evolucion_por_sucursal(db: Session, f: Filtros) -> list[dict]:
    """Ventas e ingresos en el tiempo de cada sucursal. Por día hasta un mes; por semana en rangos más largos."""
    semanal = (f.fecha_fin - f.fecha_inicio).days > 31
    dia = func.date(func.timezone("America/La_Paz", Venta.creada_en))
    if f.categoria_ids or f.producto_ids:
        q = _con_items(_ventas(db, f, Venta.sucursal_id, dia, func.count(func.distinct(Venta.id)), _SUBTOTAL), f)
    else:
        q = _ventas(db, f, Venta.sucursal_id, dia, func.count(Venta.id), func.sum(Venta.total))

    def periodo(d: date) -> date:
        return d - timedelta(days=d.weekday()) if semanal else d

    acumulado: dict[tuple[int, date], list[float]] = {}
    for sucursal_id, d, c, t in q.group_by(Venta.sucursal_id, dia).all():
        d = d if isinstance(d, date) else date.fromisoformat(str(d)[:10])
        par = acumulado.setdefault((sucursal_id, periodo(d)), [0, 0.0])
        par[0] += int(c)
        par[1] += _num(t)

    paso = timedelta(days=7 if semanal else 1)
    periodos, actual = [], periodo(f.fecha_inicio)
    while actual <= f.fecha_fin:
        periodos.append(actual)
        actual += paso
    filas = []
    for sucursal_id, nombre in sucursales_del_reporte(db, f):
        for p in periodos:  # períodos sin ventas en 0, para que las líneas sean comparables
            c, t = acumulado.get((sucursal_id, p), (0, 0.0))
            filas.append({"sucursal": nombre, "etiqueta": p.isoformat(), "ventas": c, "ingresos": round(t, 2)})
    return filas


# ---------------------------------------------------------------- estimaciones del modelo de ML (CU15)

class SinModeloEntrenado(Exception):
    """La empresa todavía no entrenó el modelo de demanda en el Dashboard analítico."""


def modelo_demanda(db: Session, empresa_id: int) -> ModeloML | None:
    return (
        db.query(ModeloML)
        .filter(ModeloML.empresa_id == empresa_id, ModeloML.tipo == "demanda")
        .order_by(ModeloML.version.desc())
        .first()
    )


def _series_demanda(db: Session, f: Filtros) -> dict:
    modelo = modelo_demanda(db, f.empresa_id)
    if modelo is None or not (modelo.resultado or {}).get("series"):
        raise SinModeloEntrenado()
    return modelo.resultado["series"]


def _categorias_pedidas(db: Session, f: Filtros) -> set[str]:
    if not f.categoria_ids:
        return set()
    return {n for (n,) in db.query(Categoria.nombre).filter(Categoria.id.in_(f.categoria_ids))}


def _variacion(antes: float, despues: float) -> float | None:
    return round((despues - antes) / antes * 100, 1) if antes > 0 else None


def _filas_estimacion(por_categoria: list[dict], categorias: set[str], sucursal: str | None = None) -> list[dict]:
    filas = []
    for c in por_categoria:
        if categorias and c["categoria"] not in categorias:
            continue
        antes, despues = round(_num(c["ultimos_30"]), 1), round(_num(c["proximos_30"]), 1)
        fila = {"etiqueta": c["categoria"], "ultimos_30": antes, "proximos_30": despues,
                "variacion_pct": _variacion(antes, despues)}
        filas.append({"sucursal": sucursal, **fila} if sucursal else fila)
    return sorted(filas, key=lambda x: -x["proximos_30"])


def prediccion_demanda(db: Session, f: Filtros) -> list[dict]:
    """Lo que el modelo supervisado (Random Forest) estima vender en los próximos 30 días, por categoría."""
    series = _series_demanda(db, f)
    if not f.sucursal_ids:
        return _filas_estimacion(series.get("total", {}).get("por_categoria", []), _categorias_pedidas(db, f))
    # Varias sucursales pedidas: se suman sus estimaciones categoría por categoría.
    suma: dict[str, dict] = {}
    for sucursal_id in f.sucursal_ids:
        for c in series.get(str(sucursal_id), {}).get("por_categoria", []):
            acc = suma.setdefault(c["categoria"], {"categoria": c["categoria"], "ultimos_30": 0.0, "proximos_30": 0.0})
            acc["ultimos_30"] += _num(c["ultimos_30"])
            acc["proximos_30"] += _num(c["proximos_30"])
    return _filas_estimacion(list(suma.values()), _categorias_pedidas(db, f))


def prediccion_por_sucursal(db: Session, f: Filtros) -> list[dict]:
    """La estimación del modelo para cada sucursal, por categoría (el modelo se entrena por empresa y sucursal)."""
    series = _series_demanda(db, f)
    categorias = _categorias_pedidas(db, f)
    bloques = []
    for sucursal_id, nombre in sucursales_del_reporte(db, f):
        serie = series.get(str(sucursal_id))
        if serie:
            bloques.append(_filas_estimacion(serie.get("por_categoria", []), categorias, nombre))
    bloques.sort(key=lambda b: -sum(x["proximos_30"] for x in b))
    return [fila for bloque in bloques for fila in bloque]


def _col(clave: str, titulo: str, tipo: str = "numero") -> dict:
    return {"clave": clave, "titulo": titulo, "tipo": tipo}


TIPOS: dict[str, TipoReporte] = {t.id: t for t in [
    TipoReporte("ventas_por_sucursal", "Ventas por sucursal", "Ventas, unidades e ingresos de cada sucursal.", True, "barras",
                [_col("etiqueta", "Sucursal", "texto"), _col("ventas", "Ventas"), _col("unidades", "Unidades"), _col("ingresos", "Ingresos", "moneda")],
                ventas_por_sucursal, ejemplo="Ventas de septiembre agrupadas por sucursal"),
    TipoReporte("ventas_por_categoria", "Ventas por categoría", "Unidades e ingresos de cada categoría de prenda.", True, "torta",
                [_col("etiqueta", "Categoría", "texto"), _col("unidades", "Unidades"), _col("ingresos", "Ingresos", "moneda")],
                ventas_por_categoria, ejemplo="¿Qué categorías vendieron más este mes?"),
    TipoReporte("ventas_por_producto", "Productos más vendidos", "Ranking de prendas por unidades vendidas.", True, "barras",
                [_col("etiqueta", "Producto", "texto"), _col("unidades", "Unidades"), _col("ingresos", "Ingresos", "moneda")],
                ventas_por_producto, usa_productos=True, usa_limite=True, ejemplo="Top 5 de productos más vendidos de la última semana"),
    TipoReporte("ventas_por_dia", "Evolución de ventas", "Ventas e ingresos día por día.", True, "lineas",
                [_col("etiqueta", "Fecha", "fecha"), _col("ventas", "Ventas"), _col("ingresos", "Ingresos", "moneda")],
                ventas_por_dia, usa_productos=True, ejemplo="¿Cómo evolucionaron las ventas en octubre?"),
    TipoReporte("ventas_por_canal", "Ventas por canal", "Ventas en tienda frente a ventas online.", True, "torta",
                [_col("etiqueta", "Canal", "texto"), _col("ventas", "Ventas"), _col("ingresos", "Ingresos", "moneda")],
                ventas_por_canal, usa_categorias=False, ejemplo="Ventas online contra presenciales del último mes"),
    TipoReporte("mejores_clientes", "Mejores clientes", "Clientes que más compraron (monto y cantidad de compras).", True, "barras",
                [_col("etiqueta", "Cliente", "texto"), _col("compras", "Compras"), _col("monto", "Monto", "moneda")],
                mejores_clientes, usa_categorias=False, usa_limite=True, ejemplo="Los 10 clientes que más compraron este trimestre"),
    TipoReporte("inventario_por_sucursal", "Inventario por sucursal", "Unidades disponibles y reservadas hoy en cada sucursal.", False, "barras",
                [_col("etiqueta", "Sucursal", "texto"), _col("disponible", "Disponible"), _col("reservado", "Reservado")],
                inventario_por_sucursal, usa_productos=True, ejemplo="¿Cuánto stock hay de chaquetas en cada sucursal?"),
    TipoReporte("stock_bajo", "Prendas con stock bajo", "Prendas en o por debajo de su stock mínimo.", False, "barras",
                [_col("etiqueta", "Prenda · sucursal", "texto"), _col("disponible", "Disponible"), _col("minimo", "Mínimo")],
                stock_bajo, ejemplo="¿Qué prendas están por agotarse?"),
    TipoReporte("reservas_por_estado", "Reservas por estado", "Cantidad de reservas pendientes, confirmadas, atendidas y canceladas.", True, "torta",
                [_col("etiqueta", "Estado", "texto"), _col("reservas", "Reservas")],
                reservas_por_estado, usa_productos=True, ejemplo="Reservas de la última semana por estado"),
    TipoReporte("productos_por_sucursal", "Productos más vendidos por sucursal",
                "Ranking de prendas más vendidas dentro de cada sucursal (top N de cada una).", True, "barras",
                [_col("sucursal", "Sucursal", "texto"), _col("etiqueta", "Producto", "texto"), _col("unidades", "Unidades"),
                 _col("ingresos", "Ingresos", "moneda")],
                productos_por_sucursal, usa_productos=True, usa_limite=True, agrupa_por_sucursal=True,
                ejemplo="Los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal"),
    TipoReporte("evolucion_por_sucursal", "Evolución de ventas por sucursal",
                "Ingresos a lo largo del tiempo en cada sucursal, para compararlas (por día o por semana).", True, "lineas",
                [_col("sucursal", "Sucursal", "texto"), _col("etiqueta", "Período", "fecha"), _col("ventas", "Ventas"),
                 _col("ingresos", "Ingresos", "moneda")],
                evolucion_por_sucursal, usa_productos=True, agrupa_por_sucursal=True,
                ejemplo="¿Cómo evolucionaron las ventas de cada sucursal en los últimos 3 meses?"),
    TipoReporte("prediccion_demanda", "Estimación de demanda (próximos 30 días)",
                "Unidades que el modelo de Machine Learning entrenado estima vender en los próximos 30 días, por "
                "categoría, frente a lo vendido en los últimos 30 (predicción, no ventas reales).", False, "barras",
                [_col("etiqueta", "Categoría", "texto"), _col("ultimos_30", "Vendido últimos 30 días"),
                 _col("proximos_30", "Estimado próximos 30 días"), _col("variacion_pct", "Variación", "porcentaje")],
                prediccion_demanda, requiere="analitica_ml",
                ejemplo="¿Cuánto estimamos vender en los próximos 30 días?"),
    TipoReporte("prediccion_por_sucursal", "Estimación de demanda por sucursal",
                "La estimación del modelo de Machine Learning para los próximos 30 días en cada sucursal, por "
                "categoría (predicción, no ventas reales).", False, "barras",
                [_col("sucursal", "Sucursal", "texto"), _col("etiqueta", "Categoría", "texto"),
                 _col("ultimos_30", "Vendido últimos 30 días"), _col("proximos_30", "Estimado próximos 30 días"),
                 _col("variacion_pct", "Variación", "porcentaje")],
                prediccion_por_sucursal, agrupa_por_sucursal=True, requiere="analitica_ml",
                ejemplo="Estimación de demanda del próximo mes en cada sucursal"),
]}

# Medida que se grafica para cada tipo (la primera columna numérica relevante).
MEDIDA_GRAFICO = {
    "ventas_por_sucursal": "ingresos", "ventas_por_categoria": "ingresos", "ventas_por_producto": "unidades",
    "ventas_por_dia": "ingresos", "ventas_por_canal": "ingresos", "mejores_clientes": "monto",
    "inventario_por_sucursal": "disponible", "stock_bajo": "disponible", "reservas_por_estado": "reservas",
    "productos_por_sucursal": "unidades", "evolucion_por_sucursal": "ingresos",
    "prediccion_demanda": "proximos_30", "prediccion_por_sucursal": "proximos_30",
}
