"""Exportación de reportes a PDF y Excel (CU14 / CU15).

Recibe los datos ya calculados (`service.contexto_reporte`) y, opcionalmente, el texto
redactado por la IA para un reporte generativo. Las cifras de las tablas siempre salen
de la base de datos, nunca del texto de la IA.
"""
import re
from datetime import datetime
from io import BytesIO
from xml.sax.saxutils import escape

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from app.shared.core.tiempo import ZONA_HORARIA_LOCAL

COLOR_HEADER = "1F2937"
COLOR_ZEBRA = "F3F4F6"
COLOR_MUTED = "6B7280"


def _bs(valor: float) -> str:
    return f"Bs {valor:,.2f}"


def _secciones(datos: dict) -> list[tuple[str, list[str], list[list]]]:
    """(título, encabezados, filas) de cada tabla del reporte, en el orden en que se muestran."""
    v, r = datos["ventas"], datos["resumen"]
    variacion = v["variacion_ingresos_pct"]
    secciones = [
        (
            "Indicadores",
            ["Indicador", "Valor"],
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
        ),
    ]
    if datos["ventas_por_sucursal"]:
        secciones.append((
            "Ventas por sucursal",
            ["Sucursal", "Ventas", "Ingresos"],
            [[s["nombre_sucursal"], s["cantidad_ventas"], _bs(s["ingresos"])] for s in datos["ventas_por_sucursal"]],
        ))
    if datos["ventas_por_categoria"]:
        secciones.append((
            "Ventas por categoría",
            ["Categoría", "Unidades", "Ingresos"],
            [[c["categoria"], c["unidades"], _bs(c["ingresos"])] for c in datos["ventas_por_categoria"]],
        ))
    if datos["top_vendidos"]:
        secciones.append((
            "Productos más vendidos",
            ["Producto", "Categoría", "Unidades", "Ingresos"],
            [[p["nombre_producto"], p["nombre_categoria"] or "—", p["unidades"], _bs(p["ingresos"])]
             for p in datos["top_vendidos"]],
        ))
    dias = [d for d in datos["ventas_por_dia"] if d["cantidad"]]
    if dias:
        secciones.append((
            "Ventas por día",
            ["Fecha", "Ventas", "Ingresos"],
            [[d["fecha"], d["cantidad"], _bs(d["ingresos"])] for d in dias],
        ))
    if r["reservas_por_estado"]:
        secciones.append((
            "Reservas por estado",
            ["Estado", "Cantidad"],
            [[e["estado"].capitalize(), e["cantidad"]] for e in r["reservas_por_estado"]],
        ))
    if datos["top_reservados"]:
        secciones.append((
            "Productos más reservados",
            ["Producto", "Unidades", "Reservas"],
            [[p["nombre_producto"], p["total_unidades"], p["total_reservas"]] for p in datos["top_reservados"]],
        ))
    if datos["alertas_stock"]:
        secciones.append((
            "Alertas de stock",
            ["Prenda", "Sucursal", "Disponible", "Mínimo"],
            [[a["nombre_producto"], a["nombre_sucursal"], a["cantidad_disponible"], a["stock_minimo"]]
             for a in datos["alertas_stock"]],
        ))
    return secciones


def _subtitulo(datos: dict) -> str:
    empresa = f"{datos['empresa']} · " if datos.get("empresa") else ""
    return (
        f"{empresa}{datos['nombre_sucursal']} · últimos {datos['periodo_dias']} días · generado el "
        f"{datetime.now(ZONA_HORARIA_LOCAL).strftime('%d/%m/%Y %H:%M')}"
    )


# ---------------------------------------------------------------- texto de la IA

def _lineas_narrativa(narrativa: str) -> list[tuple[str, str]]:
    """Convierte el markdown simple que devuelve la IA en (tipo, texto): titulo, vineta o parrafo."""
    resultado = []
    for cruda in narrativa.splitlines():
        linea = cruda.strip()
        if not linea:
            continue
        if linea.startswith("#"):
            resultado.append(("titulo", linea.lstrip("#").strip()))
        elif re.match(r"^([-*•]|\d+[.)])\s+", linea):
            resultado.append(("vineta", re.sub(r"^([-*•]|\d+[.)])\s+", "", linea)))
        else:
            resultado.append(("parrafo", linea))
    return resultado


def _negritas_pdf(texto: str) -> str:
    """Escapa el texto (no es HTML confiable) y convierte **negrita** en <b>."""
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escape(texto))


def _sin_markdown(texto: str) -> str:
    return re.sub(r"\*\*(.+?)\*\*", r"\1", texto)


# ---------------------------------------------------------------- Excel

def generar_excel(datos: dict, titulo: str, narrativa: str | None = None) -> bytes:
    wb = Workbook()
    header_fill = PatternFill(start_color=COLOR_HEADER, end_color=COLOR_HEADER, fill_type="solid")
    header_font = Font(color="FFFFFF", bold=True)
    title_font = Font(bold=True, size=14, color=COLOR_HEADER)
    muted_font = Font(italic=True, color=COLOR_MUTED)

    primera = True
    if narrativa:
        ws = wb.active
        ws.title = "Reporte"
        primera = False
        ws["A1"] = titulo
        ws["A1"].font = title_font
        ws["A2"] = _subtitulo(datos)
        ws["A2"].font = muted_font
        ws.column_dimensions["A"].width = 110
        fila = 4
        for tipo, texto in _lineas_narrativa(narrativa):
            celda = ws.cell(row=fila, column=1, value=("• " if tipo == "vineta" else "") + _sin_markdown(texto))
            celda.alignment = Alignment(wrap_text=True, vertical="top")
            if tipo == "titulo":
                celda.font = Font(bold=True, size=12, color=COLOR_HEADER)
                fila += 1
            fila += 1

    for nombre, encabezados, filas in _secciones(datos):
        ws = wb.active if primera else wb.create_sheet(nombre[:31])
        if primera:
            ws.title = nombre[:31]
            primera = False
        ws["A1"] = nombre
        ws["A1"].font = title_font
        ws["A2"] = _subtitulo(datos)
        ws["A2"].font = muted_font
        ws.append([])
        ws.append(encabezados)
        fila_encabezado = ws.max_row
        for col in range(1, len(encabezados) + 1):
            celda = ws.cell(row=fila_encabezado, column=col)
            celda.fill = header_fill
            celda.font = header_font
            celda.alignment = Alignment(horizontal="center")
        for fila in filas:
            ws.append(fila)
        for col in range(1, len(encabezados) + 1):
            anchos = [len(str(encabezados[col - 1]))] + [len(str(f[col - 1])) for f in filas]
            ws.column_dimensions[get_column_letter(col)].width = min(max(anchos) + 4, 42)

    buffer = BytesIO()
    wb.save(buffer)
    return buffer.getvalue()


# ---------------------------------------------------------------- PDF

def generar_pdf(datos: dict, titulo: str, narrativa: str | None = None) -> bytes:
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=letter,
        topMargin=1.5 * cm,
        bottomMargin=1.5 * cm,
        leftMargin=1.5 * cm,
        rightMargin=1.5 * cm,
        title=titulo,
    )

    styles = getSampleStyleSheet()
    titulo_style = ParagraphStyle("TituloReporte", parent=styles["Title"], textColor=colors.HexColor(f"#{COLOR_HEADER}"))
    subtitulo_style = ParagraphStyle(
        "Subtitulo", parent=styles["Normal"], textColor=colors.HexColor(f"#{COLOR_MUTED}"), spaceAfter=6
    )
    seccion_style = ParagraphStyle(
        "Seccion", parent=styles["Heading2"], textColor=colors.HexColor(f"#{COLOR_HEADER}"), spaceBefore=14, spaceAfter=6
    )
    parrafo_style = ParagraphStyle("Parrafo", parent=styles["Normal"], fontSize=10, leading=14, spaceAfter=4)
    vineta_style = ParagraphStyle("Vineta", parent=parrafo_style, leftIndent=12, bulletIndent=2)

    def _tabla(encabezados: list[str], filas: list[list]) -> Table:
        tabla = Table([encabezados] + [[str(c) for c in f] for f in filas], repeatRows=1)
        tabla.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor(f"#{COLOR_HEADER}")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("FONTSIZE", (0, 0), (-1, -1), 9),
                    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor(f"#{COLOR_ZEBRA}")]),
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#D1D5DB")),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                    ("TOPPADDING", (0, 0), (-1, -1), 6),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ]
            )
        )
        return tabla

    elementos = [
        Paragraph(escape(titulo), titulo_style),
        Paragraph(escape(_subtitulo(datos)), subtitulo_style),
        Spacer(1, 0.3 * cm),
    ]

    if narrativa:
        for tipo, texto in _lineas_narrativa(narrativa):
            if tipo == "titulo":
                elementos.append(Paragraph(_negritas_pdf(texto), seccion_style))
            elif tipo == "vineta":
                elementos.append(Paragraph(_negritas_pdf(texto), vineta_style, bulletText="•"))
            else:
                elementos.append(Paragraph(_negritas_pdf(texto), parrafo_style))
        elementos.append(Paragraph("Datos del período", seccion_style))

    for nombre, encabezados, filas in _secciones(datos):
        elementos.append(Paragraph(escape(nombre), seccion_style))
        elementos.append(_tabla(encabezados, filas))

    doc.build(elementos)
    return buffer.getvalue()
