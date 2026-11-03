"""CU14 — Solicitar reporte generativo.

1. La IA recibe SOLO el texto del usuario y el catálogo de reportes permitidos (ningún dato
   de la base) y devuelve una intención en JSON: tipo, fechas, sucursales, categorías,
   productos, límite y gráfico sugerido.
2. El backend valida el tipo contra el catálogo cerrado y cada parámetro contra la empresa
   del usuario; lo que no pertenece a la empresa se descarta (flujo 6b).
3. Ejecuta la consulta parametrizada (siempre filtrada por la empresa) y guarda la
   solicitud en el historial.
"""
import re
import unicodedata
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Categoria, Producto
from app.modules.ia import service as ia_service
from app.modules.reportes import catalogo_reportes as catalogo
from app.modules.reportes.models import ReporteHistorial
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL

GRAFICOS = ("barras", "lineas", "torta")
MAX_DIAS_RANGO = 366
PALABRAS_PROHIBIDAS = ("borr", "elimin", "contrasen", "password", "modific", "actualiz", "insert", "drop", "delete")


def _hoy() -> date:
    return datetime.now(ZONA_HORARIA_LOCAL).date()


def _normalizar(texto: str) -> str:
    sin_tildes = unicodedata.normalize("NFD", texto.lower())
    return "".join(c for c in sin_tildes if unicodedata.category(c) != "Mn")


def ejemplos() -> list[str]:
    return [t.ejemplo for t in catalogo.TIPOS.values() if t.ejemplo][:6]


def catalogo_para_ui() -> list[dict]:
    return [
        {"id": t.id, "titulo": t.titulo, "descripcion": t.descripcion, "usa_fechas": t.usa_fechas,
         "usa_categorias": t.usa_categorias, "usa_productos": t.usa_productos, "usa_limite": t.usa_limite,
         "grafico": t.grafico}
        for t in catalogo.TIPOS.values()
    ]


# ---------------------------------------------------------------- interpretación (IA)

def _prompt_sistema() -> str:
    tipos = "\n".join(
        f'- "{t.id}": {t.descripcion}' + ("" if t.usa_fechas else " (estado actual: no usa fechas)")
        for t in catalogo.TIPOS.values()
    )
    hoy = _hoy()
    return (
        "Convertís pedidos de reportes de una tienda de ropa en una intención estructurada. "
        "No tenés acceso a datos: solo elegís el tipo de reporte y los filtros.\n"
        f"Hoy es {hoy.isoformat()} ({hoy.strftime('%A')}).\n"
        f"Tipos de reporte permitidos:\n{tipos}\n\n"
        "Respondé SOLO un objeto JSON con estas claves:\n"
        '{"tipo": uno de los ids de arriba o null, "fecha_inicio": "AAAA-MM-DD" o null, '
        '"fecha_fin": "AAAA-MM-DD" o null, "sucursales": [nombres mencionados], '
        '"categorias": [nombres mencionados], "productos": [nombres mencionados], '
        '"limite": número o null, "grafico": "barras" | "lineas" | "torta" | null}\n'
        "Reglas: si el pedido no corresponde a ningún tipo, o pide modificar, borrar o ver datos sensibles, "
        'usá "tipo": null. Si no menciona un período, dejá las fechas en null (no las inventes). '
        "Interpretá fechas relativas a hoy: 'septiembre' = todo septiembre del año en curso (o del anterior si "
        "todavía no llegó), 'la última semana' = los últimos 7 días hasta hoy, 'este mes' = desde el día 1 hasta hoy. "
        "En sucursales, categorías y productos poné SOLO lo que el usuario nombró explícitamente, tal como lo "
        "escribió; si no nombró ninguno, dejá la lista vacía []. Nunca inventes nombres.\n\n"
        "Ejemplos:\n"
        'Pedido: "ventas de septiembre agrupadas por sucursal" → {"tipo": "ventas_por_sucursal", '
        f'"fecha_inicio": "{_ejemplo_mes(9, hoy)}-01", "fecha_fin": "{_ejemplo_mes(9, hoy)}-30", "sucursales": [], '
        '"categorias": [], "productos": [], "limite": null, "grafico": null}\n'
        'Pedido: "top 5 de vestidos más vendidos esta semana en Norte" → {"tipo": "ventas_por_producto", '
        f'"fecha_inicio": "{(hoy - timedelta(days=6)).isoformat()}", "fecha_fin": "{hoy.isoformat()}", '
        '"sucursales": ["Norte"], "categorias": ["vestidos"], "productos": [], "limite": 5, "grafico": null}\n'
        'Pedido: "qué prendas se están por agotar" → {"tipo": "stock_bajo", "fecha_inicio": null, "fecha_fin": null, '
        '"sucursales": [], "categorias": [], "productos": [], "limite": null, "grafico": null}\n'
        'Pedido: "las ventas" → {"tipo": "ventas_por_dia", "fecha_inicio": null, "fecha_fin": null, '
        '"sucursales": [], "categorias": [], "productos": [], "limite": null, "grafico": null}'
    )


def _ejemplo_mes(mes: int, hoy: date) -> str:
    """'AAAA-MM' del último <mes> ya empezado (para que el ejemplo del prompt sea coherente con hoy)."""
    anio = hoy.year if hoy.month >= mes else hoy.year - 1
    return f"{anio}-{mes:02d}"


def _mencionado(nombre: str, solicitud_norm: str) -> bool:
    """¿El usuario escribió ese nombre? (alguna palabra significativa del nombre aparece en su pedido)."""
    palabras = [p for p in _normalizar(nombre).replace("-", " ").split() if len(p) >= 4]
    # "vestidos" en el pedido y "vestido" devuelto por el modelo cuentan como la misma palabra.
    return any(p.rstrip("s") in solicitud_norm for p in palabras)


MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]


def _fin_de_mes(anio: int, mes: int) -> date:
    return (date(anio + (mes == 12), mes % 12 + 1, 1)) - timedelta(days=1)


def fechas_por_reglas(solicitud: str) -> tuple[date, date] | None:
    """Expresiones de tiempo frecuentes resueltas sin IA (más confiable que un modelo chico).

    Si la frase tiene una de estas expresiones, manda sobre las fechas que proponga el modelo.
    """
    t = _normalizar(solicitud)
    hoy = _hoy()
    n = re.search(r"ultim[oa]s?\s+(\d{1,3})\s+(dias|semanas|meses)", t)
    if n:
        cantidad = int(n.group(1)) * {"dias": 1, "semanas": 7, "meses": 30}[n.group(2)]
        return hoy - timedelta(days=max(1, cantidad) - 1), hoy
    if re.search(r"\bhoy\b", t):
        return hoy, hoy
    if re.search(r"\bayer\b", t):
        return hoy - timedelta(days=1), hoy - timedelta(days=1)
    if "semana pasada" in t:
        lunes = hoy - timedelta(days=hoy.weekday() + 7)
        return lunes, lunes + timedelta(days=6)
    if "esta semana" in t:
        return hoy - timedelta(days=hoy.weekday()), hoy
    if re.search(r"ultima semana|ultimos 7", t):
        return hoy - timedelta(days=6), hoy
    if "mes pasado" in t or "mes anterior" in t:
        fin = date(hoy.year, hoy.month, 1) - timedelta(days=1)
        return date(fin.year, fin.month, 1), fin
    if "este mes" in t or "mes actual" in t or "en el mes" in t:
        return date(hoy.year, hoy.month, 1), hoy
    if re.search(r"ultimo mes", t):
        return hoy - timedelta(days=29), hoy
    if "este trimestre" in t:
        inicio_mes = 3 * ((hoy.month - 1) // 3) + 1
        return date(hoy.year, inicio_mes, 1), hoy
    if "trimestre" in t:
        return hoy - timedelta(days=89), hoy
    if re.search(r"este (ano|anio)", t):
        return date(hoy.year, 1, 1), hoy
    for i, mes in enumerate(MESES, start=1):
        m = re.search(rf"\b{mes}\b(?:\s+(?:de|del)?\s*(\d{{4}}))?", t)
        if m:
            anio = int(m.group(1)) if m.group(1) else (hoy.year if i <= hoy.month else hoy.year - 1)
            return date(anio, i, 1), min(_fin_de_mes(anio, i), hoy)
    return None


def _interpretar(db: Session, solicitud: str) -> dict | None:
    intencion = ia_service.interpretar_json(db, _prompt_sistema(), solicitud)
    if intencion is None:
        return None
    reglas = fechas_por_reglas(solicitud)
    if reglas:
        intencion["fecha_inicio"], intencion["fecha_fin"] = reglas[0].isoformat(), reglas[1].isoformat()
    # Los modelos chicos a veces "completan" listas con nombres inventados: solo se aceptan
    # los que el usuario realmente escribió.
    texto = _normalizar(solicitud)
    for clave in ("sucursales", "categorias", "productos"):
        valores = intencion.get(clave) if isinstance(intencion.get(clave), list) else []
        intencion[clave] = [v for v in valores if isinstance(v, str) and _mencionado(v, texto)]
    return intencion


# ---------------------------------------------------------------- validación

def _fecha(valor) -> date | None:
    if not valor:
        return None
    try:
        return date.fromisoformat(str(valor)[:10])
    except ValueError:
        return None


def _resolver_nombres(nombres, opciones: dict[int, str]) -> tuple[list[int], list[str]]:
    """Empareja nombres escritos por el usuario con registros de la empresa (sin tildes, por inclusión)."""
    ids, descartados = [], []
    for nombre in nombres or []:
        if not isinstance(nombre, str) or not nombre.strip():
            continue
        buscado = _normalizar(nombre).strip()
        encontrado = [i for i, n in opciones.items() if buscado in _normalizar(n) or _normalizar(n) in buscado]
        if encontrado:
            ids.extend(i for i in encontrado if i not in ids)
        else:
            descartados.append(nombre.strip())
    return ids, descartados


def validar(db: Session, usuario: Usuario, intencion: dict) -> tuple[catalogo.TipoReporte, catalogo.Filtros, dict]:
    """Valida la intención (de la IA o del formulario) contra el catálogo y la empresa.

    Devuelve el tipo, los filtros listos para ejecutar y la intención normalizada (para el historial).
    Lanza HTTPException 400 si el tipo no existe o las fechas no son válidas.
    """
    tipo = catalogo.TIPOS.get(str(intencion.get("tipo") or ""))
    if tipo is None:
        raise HTTPException(status_code=400, detail="Ese tipo de reporte no está disponible")
    empresa_id = usuario.empresa_id
    filtros = catalogo.Filtros(empresa_id=empresa_id)
    descartados: list[str] = []

    if tipo.usa_fechas:
        inicio, fin = _fecha(intencion.get("fecha_inicio")), _fecha(intencion.get("fecha_fin"))
        if inicio is None and fin is None:
            raise HTTPException(status_code=400, detail="Falta el período del reporte")
        fin = min(fin or _hoy(), _hoy())
        inicio = inicio or fin
        if inicio > fin:
            inicio, fin = fin, inicio
        if (fin - inicio).days >= MAX_DIAS_RANGO:
            inicio = fin - timedelta(days=MAX_DIAS_RANGO - 1)
        filtros.fecha_inicio, filtros.fecha_fin = inicio, fin

    sucursales = {s.id: s.nombre for s in db.query(Sucursal).filter(Sucursal.empresa_id == empresa_id)}
    ids_sucursal = intencion.get("sucursal_ids")
    if ids_sucursal is not None:  # formulario: ya vienen ids; los de otra empresa se descartan
        filtros.sucursal_ids = [i for i in ids_sucursal if i in sucursales]
        descartados += [f"sucursal #{i}" for i in ids_sucursal if i not in sucursales]
    else:
        filtros.sucursal_ids, d = _resolver_nombres(intencion.get("sucursales"), sucursales)
        descartados += [f"sucursal «{n}»" for n in d]
    if usuario.rol == "encargado_sucursal":
        filtros.sucursal_ids = [usuario.sucursal_id]  # 6c: el encargado solo ve su sucursal

    if tipo.usa_categorias:
        categorias = {c.id: c.nombre for c in db.query(Categoria).filter(Categoria.empresa_id == empresa_id)}
        ids_cat = intencion.get("categoria_ids")
        if ids_cat is not None:
            filtros.categoria_ids = [i for i in ids_cat if i in categorias]
        else:
            filtros.categoria_ids, d = _resolver_nombres(intencion.get("categorias"), categorias)
            descartados += [f"categoría «{n}»" for n in d]
    if tipo.usa_productos and (intencion.get("productos") or intencion.get("producto_ids")):
        productos = {p.id: p.nombre for p in db.query(Producto).filter(Producto.empresa_id == empresa_id)}
        ids_prod = intencion.get("producto_ids")
        if ids_prod is not None:
            filtros.producto_ids = [i for i in ids_prod if i in productos]
        else:
            filtros.producto_ids, d = _resolver_nombres(intencion.get("productos"), productos)
            descartados += [f"producto «{n}»" for n in d]
    if tipo.usa_limite:
        try:
            filtros.limite = max(1, min(50, int(intencion.get("limite") or 10)))
        except (TypeError, ValueError):
            filtros.limite = 10

    grafico = intencion.get("grafico") if intencion.get("grafico") in GRAFICOS else tipo.grafico
    normalizada = {
        "tipo": tipo.id,
        "fecha_inicio": filtros.fecha_inicio.isoformat() if filtros.fecha_inicio else None,
        "fecha_fin": filtros.fecha_fin.isoformat() if filtros.fecha_fin else None,
        "sucursal_ids": filtros.sucursal_ids,
        "categoria_ids": filtros.categoria_ids,
        "producto_ids": filtros.producto_ids,
        "limite": filtros.limite if tipo.usa_limite else None,
        "grafico": grafico,
        "descartados": descartados,
    }
    return tipo, filtros, normalizada


# ---------------------------------------------------------------- ejecución

def _descripcion_filtros(db: Session, tipo: catalogo.TipoReporte, f: catalogo.Filtros) -> list[str]:
    partes = []
    if f.fecha_inicio:
        partes.append(
            f"Del {f.fecha_inicio.strftime('%d/%m/%Y')} al {f.fecha_fin.strftime('%d/%m/%Y')}"
            if f.fecha_inicio != f.fecha_fin else f"El {f.fecha_inicio.strftime('%d/%m/%Y')}"
        )
    else:
        partes.append("Estado actual")
    def nombres(modelo, ids):
        return ", ".join(n for (n,) in db.query(modelo.nombre).filter(modelo.id.in_(ids)).order_by(modelo.nombre))
    partes.append(f"Sucursales: {nombres(Sucursal, f.sucursal_ids)}" if f.sucursal_ids else "Todas las sucursales")
    if f.categoria_ids:
        partes.append(f"Categorías: {nombres(Categoria, f.categoria_ids)}")
    if f.producto_ids:
        partes.append(f"Productos: {nombres(Producto, f.producto_ids)}")
    if tipo.usa_limite:
        partes.append(f"Top {f.limite}")
    return partes


def ejecutar(
    db: Session, usuario: Usuario, intencion: dict, solicitud: str | None, origen: str, guardar: bool = True
) -> dict:
    """Valida y ejecuta la consulta. `guardar=False` al exportar: no duplica el historial."""
    tipo, filtros, normalizada = validar(db, usuario, intencion)
    filas = tipo.ejecutar(db, filtros)
    medida = catalogo.MEDIDA_GRAFICO[tipo.id]
    numericas = [c["clave"] for c in tipo.columnas if c["tipo"] in ("numero", "moneda")]
    totales = {k: round(sum(f[k] for f in filas), 2) for k in numericas} if tipo.id != "stock_bajo" else {}

    historial = None
    if guardar:
        historial = ReporteHistorial(
            empresa_id=usuario.empresa_id, usuario_id=usuario.id, solicitud=solicitud,
            origen=origen, tipo=tipo.id, intencion=normalizada,
        )
        db.add(historial)
        db.commit()

    hay_datos = any(f.get(medida) for f in filas)
    return {
        "estado": "ok" if hay_datos else "sin_datos",
        "mensaje": None if hay_datos else "No hay datos para los filtros indicados",
        "tipo": tipo.id,
        "titulo": tipo.titulo,
        "filtros_aplicados": _descripcion_filtros(db, tipo, filtros),
        "descartados": normalizada["descartados"],
        "intencion": normalizada,
        "columnas": tipo.columnas,
        "filas": filas,
        "totales": totales,
        "grafico": normalizada["grafico"],
        "medida": medida,
        "generado_en": datetime.now(ZONA_HORARIA_LOCAL),
        "historial_id": historial.id if historial else None,
        "origen": origen,
    }


def _respuesta(estado: str, mensaje: str, **extra) -> dict:
    return {"estado": estado, "mensaje": mensaje, "ejemplos": ejemplos(), **extra}


def solicitar(db: Session, usuario: Usuario, solicitud: str) -> dict:
    """Flujo completo del CU14 a partir de una frase en lenguaje natural."""
    texto = _normalizar(solicitud)
    if any(p in texto for p in PALABRAS_PROHIBIDAS):
        return _respuesta("no_soportado", "Ese tipo de solicitud no está disponible")  # 6a

    intencion = _interpretar(db, solicitud)
    if intencion is None:  # 4a
        return _respuesta("ia_no_disponible", "El servicio de interpretación no está disponible")
    tipo = catalogo.TIPOS.get(str(intencion.get("tipo") or ""))
    if tipo is None:  # 6a
        return _respuesta("no_soportado", "Ese tipo de solicitud no está disponible")
    if tipo.usa_fechas and not (_fecha(intencion.get("fecha_inicio")) or _fecha(intencion.get("fecha_fin"))):
        # 5a: falta el período; se pregunta en vez de inventarlo.
        que = ("las reservas" if tipo.id.startswith("reservas") else
               "los mejores clientes" if tipo.id == "mejores_clientes" else
               "los productos más vendidos" if tipo.id == "ventas_por_producto" else "las ventas")
        pregunta = f"¿De qué período desea ver {que}?"
        return _respuesta("aclaracion", pregunta, pregunta=pregunta, tipo=tipo.id, intencion_parcial=intencion)
    try:
        return ejecutar(db, usuario, intencion, solicitud, "ia")
    except HTTPException as exc:
        return _respuesta("no_soportado", str(exc.detail))


def historial(db: Session, usuario: Usuario, limite: int = 15) -> list[dict]:
    filas = (
        db.query(ReporteHistorial)
        .filter(ReporteHistorial.empresa_id == usuario.empresa_id, ReporteHistorial.usuario_id == usuario.id)
        .order_by(ReporteHistorial.id.desc())
        .limit(limite)
        .all()
    )
    return [
        {"id": h.id, "solicitud": h.solicitud, "origen": h.origen, "tipo": h.tipo,
         "titulo": catalogo.TIPOS[h.tipo].titulo if h.tipo in catalogo.TIPOS else h.tipo,
         "intencion": h.intencion, "creado_en": h.creado_en}
        for h in filas
    ]
