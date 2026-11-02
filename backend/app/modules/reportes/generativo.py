"""CU14 — Solicitar reporte generativo.

El usuario pide un reporte en lenguaje natural ("ventas de la última semana en Norte").
La IA lo redacta usando solo los datos reales del período (service.contexto_reporte);
si el proveedor de IA no responde, se arma un reporte estructurado por reglas para que
el usuario igual reciba algo útil. El resultado se puede exportar a PDF o Excel.
"""
import re
import unicodedata
from datetime import datetime

from sqlalchemy.orm import Session

from app.modules.ia import service as ia_service
from app.modules.reportes import service
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL

SYSTEM_PROMPT = (
    "Sos un analista de negocio de una tienda de ropa. Te piden un reporte por escrito. "
    "Usá EXCLUSIVAMENTE los números que aparecen en 'Datos disponibles': no inventes cifras, fechas ni "
    "productos. Si lo que piden no está en los datos, decilo en una línea y seguí con lo que sí hay. "
    "Escribí en español (Bolivia), en tono profesional y directo. Usá este formato markdown simple: "
    "una primera línea '# Título del reporte', luego secciones '## ...' con párrafos cortos y viñetas '- '. "
    "Incluí: un resumen ejecutivo de 2-3 líneas, los hallazgos principales con cifras, alertas (stock bajo, "
    "caídas de ventas) y 2-4 recomendaciones accionables. Extensión: entre 15 y 35 líneas. "
    "Montos siempre en bolivianos con el formato 'Bs 1.234,50' o 'Bs 1234.50' tal como vienen."
)

SUGERENCIAS = [
    "Resumen de ventas de la última semana",
    "¿Qué categorías venden más este mes y qué me recomendás reponer?",
    "Reporte de inventario con las prendas en riesgo de agotarse",
    "Compará el rendimiento de las sucursales en los últimos 30 días",
]


def _normalizar(texto: str) -> str:
    sin_tildes = unicodedata.normalize("NFD", texto.lower())
    return "".join(c for c in sin_tildes if unicodedata.category(c) != "Mn")


def inferir_dias(solicitud: str) -> int:
    """Período pedido en la solicitud ("hoy", "semana", "3 meses"...). Por defecto, 30 días."""
    t = _normalizar(solicitud)
    numero = re.search(r"(\d{1,3})\s*(dias|semanas|meses)", t)
    if numero:
        n, unidad = int(numero.group(1)), numero.group(2)
        return max(1, min(365, n * {"dias": 1, "semanas": 7, "meses": 30}[unidad]))
    if "hoy" in t or "del dia" in t:
        return 1
    if "semana" in t:
        return 7
    if "trimestre" in t:
        return 90
    if "anio" in t or "año" in solicitud.lower():
        return 365
    return 30


def _reporte_por_reglas(datos: dict, solicitud: str) -> str:
    """Reporte estructurado sin IA: mismo formato que la IA, armado con los datos."""
    v, r = datos["ventas"], datos["resumen"]
    variacion = v["variacion_ingresos_pct"]
    tendencia = (
        f"{'subieron' if variacion >= 0 else 'bajaron'} un {abs(variacion)}% respecto al período anterior"
        if variacion is not None else "no hay datos del período anterior para comparar"
    )
    lineas = [
        f"# Reporte: {solicitud.strip().rstrip('?.') or 'resumen del período'}",
        "## Resumen ejecutivo",
        f"En los últimos {datos['periodo_dias']} días ({datos['nombre_sucursal']}) se registraron "
        f"**{v['cantidad_ventas']} ventas** por **Bs {v['ingresos']:.2f}**, con un ticket promedio de "
        f"Bs {v['ticket_promedio']:.2f}. Los ingresos {tendencia}.",
    ]
    if datos["top_vendidos"]:
        lineas.append("## Productos más vendidos")
        lineas += [f"- {p['nombre_producto']}: {p['unidades']} unidades (Bs {p['ingresos']:.2f})" for p in datos["top_vendidos"][:5]]
    if datos["ventas_por_categoria"]:
        lineas.append("## Categorías")
        lineas += [f"- {c['categoria']}: Bs {c['ingresos']:.2f} ({c['unidades']} unidades)" for c in datos["ventas_por_categoria"]]
    if datos["ventas_por_sucursal"]:
        lineas.append("## Sucursales")
        lineas += [f"- {s['nombre_sucursal']}: {s['cantidad_ventas']} ventas, Bs {s['ingresos']:.2f}" for s in datos["ventas_por_sucursal"]]
    lineas.append("## Inventario")
    lineas.append(
        f"- {r['inventario_disponible']} unidades disponibles; {r['productos_stock_bajo']} prendas con stock bajo "
        f"y {r['productos_agotados']} agotadas."
    )
    lineas += [f"- Alerta: {a['nombre_producto']} en {a['nombre_sucursal']} ({a['cantidad_disponible']} u.)"
               for a in datos["alertas_stock"][:5]]
    lineas.append("## Recomendaciones")
    if datos["alertas_stock"]:
        lineas.append("- Reponer o transferir stock de las prendas en alerta antes de que se agoten.")
    if datos["top_vendidos"]:
        lineas.append(f"- Asegurar disponibilidad de {datos['top_vendidos'][0]['nombre_producto']}, el más vendido.")
    if variacion is not None and variacion < 0:
        lineas.append("- Revisar promociones: los ingresos cayeron respecto al período anterior.")
    lineas.append("- Revisar este reporte de nuevo al cierre de la próxima semana.")
    return "\n".join(lineas)


def _normalizar_formato(contenido: str, solicitud: str) -> str:
    """Los modelos chicos no siempre respetan el formato pedido: se corrige lo más común.

    - Una línea que es toda **negrita** se toma como encabezado de sección.
    - Si no empieza con '# Título', se agrega uno a partir de la solicitud.
    """
    lineas = []
    for linea in contenido.strip().splitlines():
        solo_negrita = re.fullmatch(r"\s*\*\*(.+?)\*\*:?\s*", linea)
        lineas.append(f"## {solo_negrita.group(1).strip().rstrip(':')}" if solo_negrita else linea)
    if not lineas or not lineas[0].lstrip().startswith("# "):
        titulo = solicitud.strip().rstrip("?.").capitalize() or "Reporte del período"
        lineas.insert(0, f"# {titulo[:100]}")
    return "\n".join(lineas)


def _titulo(contenido: str, solicitud: str) -> str:
    primera = next((l.strip() for l in contenido.splitlines() if l.strip()), "")
    if primera.startswith("#"):
        return primera.lstrip("#").strip()[:120]
    return f"Reporte: {solicitud.strip()[:100]}"


def generar(db: Session, usuario: Usuario, solicitud: str, sucursal_id: int | None, dias: int | None) -> dict:
    dias = dias or inferir_dias(solicitud)
    datos, texto_datos = service.contexto_reporte(db, usuario, sucursal_id, dias)
    # Un reporte es más largo que una respuesta de chat: un modelo local en CPU puede tardar ~1-2 min.
    contenido = ia_service._generar_respuesta_ia(
        db, solicitud, texto_datos, None, SYSTEM_PROMPT, timeout_s=150.0, max_tokens=900
    )
    generado_con_ia = bool(contenido)
    contenido = _normalizar_formato(contenido, solicitud) if contenido else _reporte_por_reglas(datos, solicitud)
    return {
        "titulo": _titulo(contenido, solicitud),
        "contenido": contenido,
        "generado_con_ia": generado_con_ia,
        "periodo_dias": dias,
        "nombre_sucursal": datos["nombre_sucursal"],
        "generado_en": datetime.now(ZONA_HORARIA_LOCAL),
        "sugerencias": SUGERENCIAS,
    }
