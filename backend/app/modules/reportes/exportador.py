"""Exportación de reportes a PDF y Excel (RF-22).

- Dashboard (CU15): indicadores y tablas del período.
- Reporte solicitado (CU14): logotipo de la empresa, título, filtros aplicados, gráfico y
  tabla con totales. En Excel el gráfico es nativo (editable).
Las cifras siempre salen de la base de datos.
"""
from datetime import datetime
from io import BytesIO
from xml.sax.saxutils import escape

import httpx
from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, PieChart, Reference
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from reportlab.graphics.charts.barcharts import HorizontalBarChart
from reportlab.graphics.charts.linecharts import HorizontalLineChart
from reportlab.graphics.charts.piecharts import Pie
from reportlab.graphics.shapes import Drawing, Rect, String
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Image, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.shared.core.tiempo import ZONA_HORARIA_LOCAL

COLOR_HEADER = "1F2937"
COLOR_ZEBRA = "F3F4F6"
COLOR_MUTED = "6B7280"
COLOR_MARCA = "A34353"  # mismo tono que los gráficos de la web
# Paleta categórica para tortas (orden fijo; validada para daltonismo).
PALETA = ["2A78D6", "EB6834", "1BAF7A", "EDA100", "E87BA4", "008300", "6250D6", "E34948"]


def _bs(valor: float) -> str:
    return f"Bs {valor:,.2f}"


def _ahora() -> str:
    return datetime.now(ZONA_HORARIA_LOCAL).strftime("%d/%m/%Y %H:%M")


def _estilos():
    styles = getSampleStyleSheet()
    return {
        "titulo": ParagraphStyle("TituloReporte", parent=styles["Title"], textColor=colors.HexColor(f"#{COLOR_HEADER}")),
        "sub": ParagraphStyle("Sub", parent=styles["Normal"], textColor=colors.HexColor(f"#{COLOR_MUTED}"), spaceAfter=4),
        "seccion": ParagraphStyle("Seccion", parent=styles["Heading2"], textColor=colors.HexColor(f"#{COLOR_HEADER}"),
                                  spaceBefore=14, spaceAfter=6),
    }


def _tabla(encabezados: list[str], filas: list[list], negrita_ultima: bool = False) -> Table:
    tabla = Table([encabezados] + [[str(c) for c in f] for f in filas], repeatRows=1)
    estilo = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(f"#{COLOR_HEADER}")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor(f"#{COLOR_ZEBRA}")]),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#D1D5DB")),
        ("ALIGN", (1, 1), (-1, -1), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    if negrita_ultima:
        estilo.append(("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"))
    tabla.setStyle(TableStyle(estilo))
    return tabla


def _documento(buffer: BytesIO, titulo: str) -> SimpleDocTemplate:
    return SimpleDocTemplate(buffer, pagesize=letter, topMargin=1.5 * cm, bottomMargin=1.5 * cm,
                             leftMargin=1.5 * cm, rightMargin=1.5 * cm, title=titulo)


def _logo(url: str | None):
    """Logotipo de la empresa para el encabezado (RF-22). Si no se puede descargar, se omite."""
    if not url:
        return None
    try:
        respuesta = httpx.get(url, timeout=5.0, follow_redirects=True)
        respuesta.raise_for_status()
        imagen = Image(BytesIO(respuesta.content))
        escala = min(3.5 * cm / imagen.imageWidth, 1.6 * cm / imagen.imageHeight)
        imagen.drawWidth, imagen.drawHeight = imagen.imageWidth * escala, imagen.imageHeight * escala
        imagen.hAlign = "LEFT"
        return imagen
    except Exception:
        return None


# ======================================================================
# Dashboard (CU15)
# ======================================================================

def _secciones_dashboard(datos: dict) -> list[tuple[str, list[str], list[list]]]:
    v, r = datos["ventas"], datos["resumen"]
    variacion = v["variacion_ingresos_pct"]
    secciones = [(
        "Indicadores", ["Indicador", "Valor"],
        [
            ["Ventas completadas", v["cantidad_ventas"]],
            ["Ingresos", _bs(v["ingresos"])],
            ["Ticket promedio", _bs(v["ticket_promedio"])],
            ["Unidades vendidas", v["unidades_vendidas"]],
            ["Variación de ingresos", f"{variacion}%" if variacion is not None else "—"],
            ["Reservas totales", r["total_reservas"]],
            ["Inventario disponible", r["inventario_disponible"]],
            ["Prendas con stock bajo", r["productos_stock_bajo"]],
            ["Prendas agotadas", r["productos_agotados"]],
        ],
    )]
    if datos["ventas_por_sucursal"]:
        secciones.append(("Ventas por sucursal", ["Sucursal", "Ventas", "Ingresos"],
                          [[s["nombre_sucursal"], s["cantidad_ventas"], _bs(s["ingresos"])] for s in datos["ventas_por_sucursal"]]))
    if datos["ventas_por_categoria"]:
        secciones.append(("Ventas por categoría", ["Categoría", "Unidades", "Ingresos"],
                          [[c["categoria"], c["unidades"], _bs(c["ingresos"])] for c in datos["ventas_por_categoria"]]))
    if datos["top_vendidos"]:
        secciones.append(("Productos más vendidos", ["Producto", "Categoría", "Unidades", "Ingresos"],
                          [[p["nombre_producto"], p["nombre_categoria"] or "—", p["unidades"], _bs(p["ingresos"])]
                           for p in datos["top_vendidos"]]))
    dias = [d for d in datos["ventas_por_dia"] if d["cantidad"]]
    if dias:
        secciones.append(("Ventas por día", ["Fecha", "Ventas", "Ingresos"],
                          [[d["fecha"], d["cantidad"], _bs(d["ingresos"])] for d in dias]))
    if r["reservas_por_estado"]:
        secciones.append(("Reservas por estado", ["Estado", "Cantidad"],
                          [[e["estado"].capitalize(), e["cantidad"]] for e in r["reservas_por_estado"]]))
    if datos["alertas_stock"]:
        secciones.append(("Alertas de stock", ["Prenda", "Sucursal", "Disponible", "Mínimo"],
                          [[a["nombre_producto"], a["nombre_sucursal"], a["cantidad_disponible"], a["stock_minimo"]]
                           for a in datos["alertas_stock"]]))
    return secciones


def _subtitulo_dashboard(datos: dict) -> str:
    empresa = f"{datos['empresa']} · " if datos.get("empresa") else ""
    return f"{empresa}{datos['nombre_sucursal']} · últimos {datos['periodo_dias']} días · generado el {_ahora()}"


def generar_pdf(datos: dict, titulo: str) -> bytes:
    buffer, e = BytesIO(), _estilos()
    elementos = [Paragraph(escape(titulo), e["titulo"]), Paragraph(escape(_subtitulo_dashboard(datos)), e["sub"]),
                 Spacer(1, 0.3 * cm)]
    for nombre, encabezados, filas in _secciones_dashboard(datos):
        elementos += [Paragraph(escape(nombre), e["seccion"]), _tabla(encabezados, filas)]
    _documento(buffer, titulo).build(elementos)
    return buffer.getvalue()


def _hoja(ws, titulo: str, subtitulo: str, encabezados: list[str], filas: list[list]) -> int:
    """Escribe título, subtítulo y tabla con encabezado oscuro. Devuelve la fila del encabezado."""
    ws["A1"] = titulo
    ws["A1"].font = Font(bold=True, size=14, color=COLOR_HEADER)
    ws["A2"] = subtitulo
    ws["A2"].font = Font(italic=True, color=COLOR_MUTED)
    ws.append([])
    ws.append(encabezados)
    fila_enc = ws.max_row
    for col in range(1, len(encabezados) + 1):
        celda = ws.cell(row=fila_enc, column=col)
        celda.fill = PatternFill(start_color=COLOR_HEADER, end_color=COLOR_HEADER, fill_type="solid")
        celda.font = Font(color="FFFFFF", bold=True)
        celda.alignment = Alignment(horizontal="center")
    for fila in filas:
        ws.append(fila)
    for col in range(1, len(encabezados) + 1):
        anchos = [len(str(encabezados[col - 1]))] + [len(str(f[col - 1])) for f in filas]
        ws.column_dimensions[get_column_letter(col)].width = min(max(anchos) + 4, 45)
    return fila_enc


def generar_excel(datos: dict, titulo: str) -> bytes:
    wb = Workbook()
    for i, (nombre, encabezados, filas) in enumerate(_secciones_dashboard(datos)):
        ws = wb.active if i == 0 else wb.create_sheet(nombre[:31])
        ws.title = nombre[:31]
        _hoja(ws, nombre if i else titulo, _subtitulo_dashboard(datos), encabezados, filas)
    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


# ======================================================================
# Reporte solicitado (CU14)
# ======================================================================

def _valor(col: dict, valor) -> str:
    if valor is None:
        return "—"
    if col["tipo"] == "porcentaje":
        return f"{'+' if valor > 0 else ''}{valor:.0f}%"
    if col["tipo"] == "moneda":
        return _bs(float(valor))
    if col["tipo"] == "numero":
        return f"{valor:,}" if isinstance(valor, int) else f"{valor:,.2f}"
    return str(valor)


def _grafico_pdf(resultado: dict) -> Drawing | None:
    filas, medida = resultado["filas"], resultado["medida"]
    if not filas:
        return None
    tipo = resultado["grafico"]
    agrupado = "sucursal" in filas[0]
    if agrupado and tipo == "lineas":
        return _lineas_por_sucursal(filas, medida)
    if resultado.get("tipo") == "evolucion_por_sucursal":
        # En barras o torta, la evolución se compara por su total en cada sucursal.
        totales: dict[str, float] = {}
        for f in filas:
            totales[f["sucursal"]] = totales.get(f["sucursal"], 0.0) + float(f[medida] or 0)
        etiquetas, valores = list(totales), list(totales.values())
    else:
        # En los reportes por sucursal cada barra/porción lleva su sucursal: "Centro · Camiseta".
        etiquetas = [(f"{f['sucursal']} · {f['etiqueta']}" if agrupado else str(f["etiqueta"]))[:34] for f in filas]
        valores = [float(f[medida] or 0) for f in filas]
    if tipo == "torta":
        # Más de 6 porciones no se leen: el resto se agrupa en "Otros".
        if len(valores) > 6:
            etiquetas, valores = etiquetas[:5] + ["Otros"], valores[:5] + [sum(valores[5:])]
        d = Drawing(460, 200)
        pie = Pie()
        pie.x, pie.y, pie.width, pie.height = 30, 15, 170, 170
        pie.data, pie.labels = valores, None
        pie.slices.strokeColor, pie.slices.strokeWidth = colors.white, 1.5
        for i in range(len(valores)):
            pie.slices[i].fillColor = colors.HexColor(f"#{PALETA[i % len(PALETA)]}")
        d.add(pie)
        total = sum(valores) or 1
        for i, (etq, val) in enumerate(zip(etiquetas, valores)):
            y = 175 - i * 22
            d.add(Rect(230, y, 10, 10, fillColor=colors.HexColor(f"#{PALETA[i % len(PALETA)]}"), strokeColor=None))
            d.add(String(246, y + 1, f"{etq} — {val / total * 100:.0f}%", fontSize=9, fillColor=colors.HexColor("#374151")))
        return d
    if tipo == "lineas":
        d = Drawing(500, 200)
        lc = HorizontalLineChart()
        lc.x, lc.y, lc.width, lc.height = 45, 30, 430, 150
        lc.data = [valores]
        paso = max(1, len(etiquetas) // 8)
        lc.categoryAxis.categoryNames = [e if i % paso == 0 else "" for i, e in enumerate(etiquetas)]
        lc.categoryAxis.labels.fontSize, lc.valueAxis.labels.fontSize = 7, 7
        lc.categoryAxis.labels.angle, lc.categoryAxis.labels.dy = 30, -8
        lc.valueAxis.valueMin = 0
        lc.lines[0].strokeColor, lc.lines[0].strokeWidth = colors.HexColor(f"#{COLOR_MARCA}"), 2
        d.add(lc)
        return d
    # barras horizontales: etiquetas largas (productos, sucursales) se leen mejor
    alto = max(120, min(600, 22 * len(valores) + 30))  # acotado: tiene que entrar en una página
    d = Drawing(500, alto)
    bc = HorizontalBarChart()
    bc.x, bc.y, bc.width, bc.height = 150, 15, 320, alto - 30
    bc.data = [list(reversed(valores))]
    bc.categoryAxis.categoryNames = list(reversed(etiquetas))
    bc.categoryAxis.labels.fontSize, bc.valueAxis.labels.fontSize = 8, 7
    bc.valueAxis.valueMin = 0
    bc.bars[0].fillColor, bc.bars[0].strokeColor = colors.HexColor(f"#{COLOR_MARCA}"), None
    bc.barSpacing = 2
    d.add(bc)
    return d


def _lineas_por_sucursal(filas: list[dict], medida: str) -> Drawing:
    """Una línea por sucursal sobre los mismos períodos, con su leyenda (evolución comparada)."""
    periodos = list(dict.fromkeys(str(f["etiqueta"]) for f in filas))
    sucursales = list(dict.fromkeys(f["sucursal"] for f in filas))
    valores = {(f["sucursal"], str(f["etiqueta"])): float(f[medida] or 0) for f in filas}
    d = Drawing(500, 220)
    lc = HorizontalLineChart()
    lc.x, lc.y, lc.width, lc.height = 45, 45, 430, 150
    lc.data = [[valores.get((s, p), 0.0) for p in periodos] for s in sucursales]
    paso = max(1, len(periodos) // 8)
    lc.categoryAxis.categoryNames = [p if i % paso == 0 else "" for i, p in enumerate(periodos)]
    lc.categoryAxis.labels.fontSize, lc.valueAxis.labels.fontSize = 7, 7
    lc.categoryAxis.labels.angle, lc.categoryAxis.labels.dy = 30, -8
    lc.valueAxis.valueMin = 0
    for i in range(len(sucursales)):
        lc.lines[i].strokeColor, lc.lines[i].strokeWidth = colors.HexColor(f"#{PALETA[i % len(PALETA)]}"), 2
    d.add(lc)
    for i, s in enumerate(sucursales):
        x = 45 + i * 140
        d.add(Rect(x, 205, 10, 10, fillColor=colors.HexColor(f"#{PALETA[i % len(PALETA)]}"), strokeColor=None))
        d.add(String(x + 16, 206, s[:20], fontSize=9, fillColor=colors.HexColor("#374151")))
    return d


def _tabla_consulta(resultado: dict) -> tuple[list[str], list[list]]:
    cols = resultado["columnas"]
    filas = [[_valor(c, f[c["clave"]]) for c in cols] for f in resultado["filas"]]
    if resultado["totales"]:
        filas.append(["Total"] + [_valor(c, resultado["totales"][c["clave"]]) if c["clave"] in resultado["totales"] else ""
                                  for c in cols[1:]])
    return [c["titulo"] for c in cols], filas


def exportar_consulta_pdf(resultado: dict, empresa_nombre: str, logo_url: str | None) -> bytes:
    buffer, e = BytesIO(), _estilos()
    elementos = []
    logo = _logo(logo_url)
    if logo:
        elementos.append(logo)
    elementos += [
        Paragraph(escape(resultado["titulo"]), e["titulo"]),
        Paragraph(escape(f"{empresa_nombre} · generado el {_ahora()}"), e["sub"]),
        Paragraph(escape(" · ".join(resultado["filtros_aplicados"])), e["sub"]),
    ]
    if resultado.get("solicitud"):
        elementos.append(Paragraph(f"Solicitud: <i>{escape(resultado['solicitud'])}</i>", e["sub"]))
    if resultado.get("resumen"):
        elementos += [Spacer(1, 0.2 * cm), Paragraph(escape(resultado["resumen"]), e["sub"])]
    grafico = _grafico_pdf(resultado)
    if grafico:
        elementos += [Spacer(1, 0.4 * cm), grafico]
    encabezados, filas = _tabla_consulta(resultado)
    elementos += [Paragraph("Detalle", e["seccion"]), _tabla(encabezados, filas, negrita_ultima=bool(resultado["totales"]))]
    _documento(buffer, resultado["titulo"]).build(elementos)
    return buffer.getvalue()


def exportar_consulta_excel(resultado: dict, empresa_nombre: str) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Reporte"
    encabezados, _ = _tabla_consulta(resultado)
    cols = resultado["columnas"]
    # En Excel van los números reales (no texto formateado) para que se puedan sumar y graficar.
    filas = [[f[c["clave"]] for c in cols] for f in resultado["filas"]]
    subtitulo = f"{empresa_nombre} · {' · '.join(resultado['filtros_aplicados'])} · generado el {_ahora()}"
    fila_enc = _hoja(ws, resultado["titulo"], subtitulo, encabezados, filas)
    primera, ultima = fila_enc + 1, fila_enc + len(filas)
    for i, c in enumerate(cols, start=1):
        if c["tipo"] == "moneda":
            for fila in range(primera, ultima + 1):
                ws.cell(row=fila, column=i).number_format = '"Bs" #,##0.00'
    if resultado["totales"]:
        ws.append(["Total"] + [resultado["totales"].get(c["clave"], "") for c in cols[1:]])
        for celda in ws[ws.max_row]:
            celda.font = Font(bold=True)

    if filas:
        col_medida = next(i for i, c in enumerate(cols, start=1) if c["clave"] == resultado["medida"])
        datos_ref = Reference(ws, min_col=col_medida, min_row=fila_enc, max_row=ultima)
        col_etiqueta = next(i for i, c in enumerate(cols, start=1) if c["clave"] == "etiqueta")
        etiquetas_ref = Reference(ws, min_col=col_etiqueta, min_row=primera, max_row=ultima)
        tipo = resultado["grafico"]
        chart = PieChart() if tipo == "torta" else LineChart() if tipo == "lineas" else BarChart()
        if isinstance(chart, BarChart):
            chart.type = "bar"
        chart.title = resultado["titulo"]
        chart.add_data(datos_ref, titles_from_data=True)
        chart.set_categories(etiquetas_ref)
        chart.height, chart.width = 9, 18
        ws.add_chart(chart, f"{get_column_letter(len(cols) + 2)}{fila_enc}")

    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()
