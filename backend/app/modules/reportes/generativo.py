"""CU14 — Solicitar reporte generativo.

1. La IA recibe SOLO el texto del usuario y el catálogo de reportes permitidos (ningún dato
   de la base) y devuelve una intención en JSON: tipo, fechas, sucursales, categorías,
   productos, límite y gráfico sugerido.
2. El backend valida el tipo contra el catálogo cerrado y cada parámetro contra la empresa
   del usuario; lo que no pertenece a la empresa se descarta (flujo 6b).
3. Ejecuta la consulta parametrizada (siempre filtrada por la empresa) y guarda la
   solicitud en el historial.
4. Responde también en lenguaje natural (un resumen de lo que muestran los datos) y sugiere
   cómo seguir. La conversación continúa: el siguiente pedido ("ahora solo Norte", "mostralo
   en torta", "¿y la estimación?") se interpreta sobre el reporte que el usuario está viendo.
"""
import json
import re
import unicodedata
from datetime import date, datetime, timedelta

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Categoria, Producto
from app.modules.empresas import service as empresas_service
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


_EJEMPLOS_DESTACADOS = (
    "productos_por_sucursal", "prediccion_por_sucursal", "evolucion_por_sucursal",
    "ventas_por_producto", "ventas_por_categoria", "stock_bajo",
)


def ejemplos() -> list[str]:
    return [catalogo.TIPOS[i].ejemplo for i in _EJEMPLOS_DESTACADOS if i in catalogo.TIPOS]


def catalogo_para_ui() -> list[dict]:
    return [
        {"id": t.id, "titulo": t.titulo, "descripcion": t.descripcion, "usa_fechas": t.usa_fechas,
         "usa_categorias": t.usa_categorias, "usa_productos": t.usa_productos, "usa_limite": t.usa_limite,
         "grafico": t.grafico, "agrupa_por_sucursal": t.agrupa_por_sucursal}
        for t in catalogo.TIPOS.values()
    ]


# ---------------------------------------------------------------- interpretación (IA)

def _prompt_sistema(previo: dict | None = None) -> str:
    tipos = "\n".join(
        f'- "{t.id}": {t.descripcion}' + ("" if t.usa_fechas else " (no usa fechas)")
        for t in catalogo.TIPOS.values()
    )
    hoy = _hoy()
    conversacion = (
        "\nCONVERSACIÓN: el usuario ya está viendo este reporte: "
        f"{json.dumps(previo, ensure_ascii=False)}.\n"
        "Si el nuevo pedido es una continuación o un ajuste (por ejemplo 'ahora solo Norte', 'mostralo en torta', "
        "'y por sucursal?', 'el mes pasado', 'solo el top 3', 'y la estimación?'), devolvé la intención COMPLETA: "
        "copiá el reporte anterior y cambiá solo lo que pide. Si es un pedido nuevo e independiente, ignorá el anterior.\n"
        if previo else ""
    )
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
        "escribió; si no nombró ninguno, dejá la lista vacía []. Nunca inventes nombres.\n"
        "Si pide los productos más vendidos 'por sucursal', 'en cada sucursal' o 'agrupados por sucursal', usá "
        '"productos_por_sucursal" (no "ventas_por_producto"). Si pide comparar la evolución de las ventas entre '
        'sucursales, usá "evolucion_por_sucursal". Si pide una estimación, predicción, proyección o lo que se va a '
        'vender, usá "prediccion_demanda" (o "prediccion_por_sucursal" si lo quiere por sucursal).\n'
        f"{conversacion}\n"
        "Ejemplos:\n"
        'Pedido: "los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal" → '
        '{"tipo": "productos_por_sucursal", '
        f'"fecha_inicio": "{(hoy - timedelta(days=89)).isoformat()}", "fecha_fin": "{hoy.isoformat()}", '
        '"sucursales": [], "categorias": [], "productos": [], "limite": 10, "grafico": null}\n'
        'Pedido: "cuánto vamos a vender el próximo mes en cada sucursal" → {"tipo": "prediccion_por_sucursal", '
        '"fecha_inicio": null, "fecha_fin": null, "sucursales": [], "categorias": [], "productos": [], '
        '"limite": null, "grafico": null}\n'
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


_POR_SUCURSAL = re.compile(
    r"(por|cada|entre|segun)\s+(la\s+|las\s+)?sucursal|agrupad\w*\s+(por\s+)?sucursal|sucursal\s+por\s+sucursal"
    r"|compar\w*\s+(las\s+)?sucursales|separad\w*\s+por\s+sucursal"
)
_ESTIMACION = re.compile(
    r"estim|predic|proyec|pronost|se va a vender|vamos a vender|venderemos|vender el proximo"
    r"|proxim[oa]s?\s+(\d+\s+)?(dias|semanas|mes)"
)
_PRODUCTOS = re.compile(r"product|prenda|articulo|mas vendid")
_EN_TOTAL = re.compile(r"en total|toda la empresa|todas las sucursales juntas|en general|global|sin separar")
_SIN_AGRUPAR = {"productos_por_sucursal": "ventas_por_producto", "evolucion_por_sucursal": "ventas_por_dia",
                "prediccion_por_sucursal": "prediccion_demanda"}
_EVOLUCION = re.compile(r"evoluci|tendencia|dia a dia|por dia|por semana|semanal|diari|en el tiempo")
_GRAFICOS = (("torta", re.compile(r"\btorta|pastel|circular")), ("lineas", re.compile(r"\blinea")),
             ("barras", re.compile(r"\bbarra")))


def _aplicar_reglas(intencion: dict, texto: str, previo: dict | None) -> None:
    """Refuerza con reglas fijas lo que un modelo chico suele confundir (el tipo y el gráfico).

    La IA sigue eligiendo el reporte; estas reglas solo corrigen casos claros, por ejemplo
    "más vendidos ... agrupados por sucursal" interpretado como un top general.
    """
    tipo = intencion.get("tipo")
    por_sucursal = bool(_POR_SUCURSAL.search(texto))
    previo_agrupado = bool(previo and catalogo.TIPOS.get(previo.get("tipo") or "") and
                           catalogo.TIPOS[previo["tipo"]].agrupa_por_sucursal)
    if _ESTIMACION.search(texto):
        en_total = bool(_EN_TOTAL.search(texto))
        agrupar = por_sucursal or (not en_total and (tipo == "prediccion_por_sucursal" or previo_agrupado))
        intencion["tipo"] = "prediccion_por_sucursal" if agrupar else "prediccion_demanda"
    elif por_sucursal:
        if tipo == "ventas_por_producto" or (tipo in (None, "ventas_por_sucursal") and _PRODUCTOS.search(texto)):
            intencion["tipo"] = "productos_por_sucursal"
        elif tipo == "ventas_por_dia" or (tipo == "ventas_por_sucursal" and _EVOLUCION.search(texto)):
            intencion["tipo"] = "evolucion_por_sucursal"
        elif tipo == "prediccion_demanda":
            intencion["tipo"] = "prediccion_por_sucursal"
    elif _EN_TOTAL.search(texto) and tipo in _SIN_AGRUPAR:
        intencion["tipo"] = _SIN_AGRUPAR[tipo]  # "ahora para toda la empresa": se deja de separar por sucursal
    for grafico, patron in _GRAFICOS:
        if patron.search(texto):
            intencion["grafico"] = grafico
            break


def _interpretar(db: Session, solicitud: str, previo: dict | None = None) -> dict | None:
    intencion = ia_service.interpretar_json(db, _prompt_sistema(previo), solicitud)
    if intencion is None:
        return None
    texto = _normalizar(solicitud)
    _aplicar_reglas(intencion, texto, previo)
    reglas = fechas_por_reglas(solicitud)
    if reglas:
        intencion["fecha_inicio"], intencion["fecha_fin"] = reglas[0].isoformat(), reglas[1].isoformat()
    # Los modelos chicos a veces "completan" listas con nombres inventados: solo se aceptan los que el
    # usuario escribió ahora o los que ya estaban en el reporte que está viendo (continuación de la charla).
    for clave in ("sucursales", "categorias", "productos"):
        valores = intencion.get(clave) if isinstance(intencion.get(clave), list) else []
        anteriores = {_normalizar(n) for n in (previo or {}).get(clave, [])}
        intencion[clave] = [
            v for v in valores
            if isinstance(v, str) and (_mencionado(v, texto) or _normalizar(v) in anteriores)
        ]
    return intencion


def _previo(db: Session, usuario: Usuario, contexto: dict | None) -> dict | None:
    """El reporte que el usuario está viendo, con nombres (no ids) para que la IA lo entienda.

    El contexto lo manda la web: los ids se vuelven a filtrar por la empresa del usuario.
    """
    if not isinstance(contexto, dict) or contexto.get("tipo") not in catalogo.TIPOS:
        return None

    def nombres(modelo, ids) -> list[str]:
        ids = [i for i in (ids or []) if isinstance(i, int)]
        if not ids:
            return []
        return [n for (n,) in db.query(modelo.nombre).filter(modelo.id.in_(ids), modelo.empresa_id == usuario.empresa_id)]

    return {
        "tipo": contexto["tipo"],
        "fecha_inicio": contexto.get("fecha_inicio"),
        "fecha_fin": contexto.get("fecha_fin"),
        "sucursales": nombres(Sucursal, contexto.get("sucursal_ids")),
        "categorias": nombres(Categoria, contexto.get("categoria_ids")),
        "productos": nombres(Producto, contexto.get("producto_ids")),
        "limite": contexto.get("limite"),
        "grafico": contexto.get("grafico"),
    }


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
    elif tipo.requiere == "analitica_ml":
        partes.append("Estimación a 30 días")
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


def _fmt(valor, moneda: bool = False) -> str:
    """Número en formato boliviano: 1.598,40 (moneda con 'Bs')."""
    valor = float(valor or 0)
    texto = f"{valor:,.2f}" if moneda else (f"{int(valor):,}" if valor.is_integer() else f"{valor:,.1f}")
    texto = texto.replace(",", "§").replace(".", ",").replace("§", ".")
    return f"Bs {texto}" if moneda else texto


def _fecha_txt(iso: str) -> str:
    try:
        return date.fromisoformat(iso[:10]).strftime("%d/%m/%Y")
    except ValueError:
        return iso


def _grupos(filas: list[dict], medida: str) -> list[dict]:
    """Filas de un reporte por sucursal → un bloque por sucursal (la web dibuja un gráfico por cada una)."""
    grupos: list[dict] = []
    por_nombre: dict[str, dict] = {}
    for f in filas:
        grupo = por_nombre.get(f["sucursal"])
        if grupo is None:
            grupo = por_nombre[f["sucursal"]] = {"nombre": f["sucursal"], "puntos": []}
            grupos.append(grupo)
        grupo["puntos"].append({"etiqueta": str(f["etiqueta"]), "valor": float(f.get(medida) or 0)})
    return grupos


def _resumen(tipo: catalogo.TipoReporte, filas: list[dict], medida: str, sin_datos: list[str]) -> str:
    """La respuesta en lenguaje natural: qué dicen los datos, sin inventar nada (se arma con las filas reales)."""
    if not filas:
        return "No hay datos para los filtros indicados."
    col = next(c for c in tipo.columnas if c["clave"] == medida)
    moneda = col["tipo"] == "moneda"
    partes: list[str] = []

    if tipo.id == "productos_por_sucursal":
        for g in _grupos(filas, "unidades"):
            p = g["puntos"]
            frase = f"En {g['nombre']}, lo más vendido fue {p[0]['etiqueta']} ({_fmt(p[0]['valor'])} u.)"
            if len(p) > 1:
                frase += f", seguido de {p[1]['etiqueta']} ({_fmt(p[1]['valor'])} u.)"
            partes.append(frase + ".")
        partes.append(f"En total se vendieron {_fmt(sum(f['unidades'] for f in filas))} unidades por "
                      f"{_fmt(sum(f['ingresos'] for f in filas), True)}.")
        if sin_datos:
            partes.append(f"Sin ventas en el período: {', '.join(sin_datos)}.")

    elif tipo.id == "evolucion_por_sucursal":
        totales = {}
        for f in filas:
            totales[f["sucursal"]] = totales.get(f["sucursal"], 0) + f["ingresos"]
        total = sum(totales.values()) or 1
        ranking = sorted(totales.items(), key=lambda x: -x[1])
        lider, monto = ranking[0]
        partes.append(f"{lider} lideró con {_fmt(monto, True)} ({monto / total * 100:.0f}% del total)")
        siguientes = [(n, m) for n, m in ranking[1:] if m]
        if siguientes:
            partes[-1] += ", seguida de " + ", ".join(f"{n} ({_fmt(m, True)})" for n, m in siguientes) + "."
        else:
            partes[-1] += "."
        mejor = max((f for f in filas if f["sucursal"] == lider), key=lambda f: f["ingresos"])
        if mejor["ingresos"]:
            partes.append(f"Su mejor período fue el del {_fecha_txt(mejor['etiqueta'])} ({_fmt(mejor['ingresos'], True)}).")
        sin_ventas = [n for n, m in ranking if not m]
        if sin_ventas:
            partes.append(f"Sin ventas en el período: {', '.join(sin_ventas)}.")

    elif tipo.id in ("prediccion_demanda", "prediccion_por_sucursal"):
        antes, despues = sum(f["ultimos_30"] for f in filas), sum(f["proximos_30"] for f in filas)
        variacion = (despues - antes) / antes * 100 if antes else None
        partes.append(
            f"El modelo estima {_fmt(round(despues))} unidades para los próximos 30 días, frente a "
            f"{_fmt(round(antes))} vendidas en los últimos 30"
            + (f" ({'+' if variacion >= 0 else ''}{variacion:.0f}%)." if variacion is not None else ".")
        )
        if tipo.id == "prediccion_por_sucursal":
            for g in _grupos(filas, "proximos_30"):
                estimado = round(sum(p["valor"] for p in g["puntos"]))
                if estimado:
                    top = max(g["puntos"], key=lambda p: p["valor"])
                    partes.append(f"{g['nombre']}: {_fmt(estimado)} u. estimadas ({top['etiqueta']} a la cabeza).")
                else:
                    partes.append(f"{g['nombre']}: no se espera demanda en los próximos 30 días.")
            if sin_datos:
                partes.append(f"Sin historial suficiente para estimar: {', '.join(sin_datos)}.")
        else:
            top = max(filas, key=lambda f: f["proximos_30"])
            partes.append(f"La categoría con más demanda esperada es {top['etiqueta']} ({_fmt(top['proximos_30'])} u.).")
            sube = [f for f in filas if f["variacion_pct"] is not None and f["ultimos_30"] >= 3]
            if sube:
                mayor = max(sube, key=lambda f: f["variacion_pct"])
                if mayor["variacion_pct"] > 0:
                    partes.append(f"La que más crece es {mayor['etiqueta']} (+{mayor['variacion_pct']:.0f}%).")
        partes.append("Es una predicción del modelo entrenado, no ventas reales.")

    elif tipo.id == "stock_bajo":
        critica = filas[0]
        partes.append(f"Hay {len(filas)} prendas en o por debajo de su stock mínimo. La más crítica es "
                      f"{critica['etiqueta']} ({critica['disponible']} disponibles, mínimo {critica['minimo']}).")

    else:
        top = max(filas, key=lambda f: f.get(medida) or 0)
        etiqueta = _fecha_txt(top["etiqueta"]) if tipo.columnas[0]["tipo"] == "fecha" else top["etiqueta"]
        if tipo.columnas[0]["tipo"] == "fecha":
            partes.append(f"El mejor día fue el {etiqueta}, con {_fmt(top[medida], moneda)}.")
        else:
            cantidad = f"{_fmt(top[medida], moneda)} de {col['titulo'].lower()}" if moneda else \
                f"{_fmt(top[medida])} {col['titulo'].lower()}"
            partes.append(f"{etiqueta} encabeza el reporte con {cantidad}.")
        if tipo.id != "stock_bajo" and len(filas) > 1:
            partes.append(f"Total: {_fmt(sum(f.get(medida) or 0 for f in filas), moneda)}.")
    return " ".join(partes)


_SUGERENCIAS = {
    "ventas_por_producto": ["Ahora agrupado por sucursal", "Mostralo en torta", "¿Y la estimación para los próximos 30 días?"],
    "productos_por_sucursal": ["Solo el top 3 de cada sucursal", "¿Cómo evolucionaron las ventas de cada sucursal?",
                               "¿Cuánto estimamos vender en cada sucursal?"],
    "evolucion_por_sucursal": ["Ahora solo el último mes", "Los productos más vendidos de cada sucursal",
                               "Estimación de demanda por sucursal"],
    "prediccion_demanda": ["Ahora por sucursal", "Mostralo en torta", "¿Qué se vendió más en los últimos 3 meses?"],
    "prediccion_por_sucursal": ["Ahora para toda la empresa", "Los productos más vendidos de cada sucursal",
                                "Mostralo en torta"],
    "ventas_por_sucursal": ["¿Cómo evolucionaron en el tiempo por sucursal?", "Los productos más vendidos de cada sucursal",
                            "Mostralo en torta"],
    "ventas_por_dia": ["Ahora separado por sucursal", "¿Y la estimación para los próximos 30 días?", "Solo el mes pasado"],
    "stock_bajo": ["¿Cuánto stock hay en cada sucursal?", "¿Cuánto estimamos vender en los próximos 30 días?",
                   "Los productos más vendidos de cada sucursal"],
    "inventario_por_sucursal": ["¿Qué prendas están por agotarse?", "Estimación de demanda por sucursal",
                                "Mostralo en torta"],
}


def _sugerencias(tipo: catalogo.TipoReporte, filas: list[dict]) -> list[str]:
    lista = list(_SUGERENCIAS.get(tipo.id, ["Ahora agrupado por sucursal", "Mostralo en torta",
                                            "¿Y la estimación para los próximos 30 días?"]))
    if tipo.agrupa_por_sucursal and filas:
        nombre = filas[0]["sucursal"]
        lista.insert(0, f"Solo la {nombre}" if _normalizar(nombre).startswith("sucursal") else f"Solo la sucursal {nombre}")
    return lista[:4]


def ejecutar(
    db: Session, usuario: Usuario, intencion: dict, solicitud: str | None, origen: str, guardar: bool = True
) -> dict:
    """Valida y ejecuta la consulta. `guardar=False` al exportar: no duplica el historial."""
    tipo, filtros, normalizada = validar(db, usuario, intencion)
    if tipo.requiere:  # las estimaciones usan el modelo de ML: el plan tiene que incluirlo (RN-05)
        empresas_service.requiere_funcionalidad(db, usuario.empresa_id, tipo.requiere)
    try:
        filas = tipo.ejecutar(db, filtros)
    except catalogo.SinModeloEntrenado:
        raise HTTPException(status_code=400, detail="Todavía no hay un modelo entrenado: entrenalo desde el "
                                                    "Dashboard analítico (Analítica con Machine Learning)")
    medida = catalogo.MEDIDA_GRAFICO[tipo.id]
    numericas = [c["clave"] for c in tipo.columnas if c["tipo"] in ("numero", "moneda")]
    totales = {k: round(sum(f[k] for f in filas), 2) for k in numericas} if tipo.id != "stock_bajo" else {}

    grupos, sin_datos = None, []
    if tipo.agrupa_por_sucursal:
        grupos = _grupos(filas, medida)
        con_datos = {g["nombre"] for g in grupos}
        sin_datos = [n for _, n in catalogo.sucursales_del_reporte(db, filtros) if n not in con_datos]
    filtros_aplicados = _descripcion_filtros(db, tipo, filtros)
    if tipo.requiere == "analitica_ml":
        modelo = catalogo.modelo_demanda(db, usuario.empresa_id)
        if modelo:
            filtros_aplicados.append(
                f"Modelo {modelo.algoritmo} v{modelo.version} · entrenado el {modelo.entrenado_en.strftime('%d/%m/%Y')}"
            )

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
        "filtros_aplicados": filtros_aplicados,
        "descartados": normalizada["descartados"],
        "intencion": normalizada,
        "columnas": tipo.columnas,
        "filas": filas,
        "totales": totales,
        "grafico": normalizada["grafico"],
        "medida": medida,
        "grupos": grupos,
        "sucursales_sin_datos": sin_datos,
        "resumen": _resumen(tipo, filas, medida, sin_datos) if hay_datos else None,
        "sugerencias": _sugerencias(tipo, filas),
        "generado_en": datetime.now(ZONA_HORARIA_LOCAL),
        "historial_id": historial.id if historial else None,
        "origen": origen,
    }


def _respuesta(estado: str, mensaje: str, **extra) -> dict:
    return {"estado": estado, "mensaje": mensaje, "ejemplos": ejemplos(), **extra}


def solicitar(db: Session, usuario: Usuario, solicitud: str, contexto: dict | None = None) -> dict:
    """Flujo completo del CU14 a partir de una frase en lenguaje natural.

    `contexto` es la intención del reporte que el usuario está viendo: con él, la frase puede ser una
    continuación de la conversación ("ahora solo Norte", "mostralo en torta").
    """
    texto = _normalizar(solicitud)
    if any(p in texto for p in PALABRAS_PROHIBIDAS):
        return _respuesta("no_soportado", "Ese tipo de solicitud no está disponible")  # 6a

    previo = _previo(db, usuario, contexto)
    intencion = _interpretar(db, solicitud, previo)
    if intencion is None:  # 4a
        return _respuesta("ia_no_disponible", "El servicio de interpretación no está disponible")
    tipo = catalogo.TIPOS.get(str(intencion.get("tipo") or ""))
    if tipo is None:  # 6a
        return _respuesta("no_soportado", "Ese tipo de solicitud no está disponible")
    if previo:
        # Continuación: lo que la frase no cambia se conserva del reporte anterior.
        if tipo.usa_fechas and not (_fecha(intencion.get("fecha_inicio")) or _fecha(intencion.get("fecha_fin"))):
            intencion["fecha_inicio"], intencion["fecha_fin"] = previo.get("fecha_inicio"), previo.get("fecha_fin")
        if tipo.usa_limite and not intencion.get("limite") and previo.get("limite"):
            intencion["limite"] = previo["limite"]
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
