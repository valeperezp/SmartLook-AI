"""Analítica con Machine Learning (CU15): datos de la empresa → motor → resultados guardados.

Los modelos se entrenan y se consultan por empresa (RN-29). Cada entrenamiento guarda el
modelo con joblib y, en la tabla modelos_ml, sus métricas y resultados ya calculados, así
el dashboard puede mostrar los últimos resultados aunque el motor no esté disponible.
"""
import os
from datetime import datetime

import joblib
import pandas as pd
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.modules.analitica_ml import models, motor
from app.modules.catalogo.models import Categoria, Producto
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.core.config import settings
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL

TOTAL = "total"


def _hoy():
    return datetime.now(ZONA_HORARIA_LOCAL).date()


# ---------------------------------------------------------------- extracción de datos

def _ventas_diarias(db: Session, empresa_id: int) -> pd.DataFrame:
    dia = func.date(func.timezone("America/La_Paz", Venta.creada_en))
    filas = (
        db.query(dia, Venta.sucursal_id, Categoria.nombre, func.sum(VentaItem.cantidad))
        .join(VentaItem, VentaItem.venta_id == Venta.id)
        .join(Producto, Producto.id == VentaItem.producto_id)
        .join(Categoria, Categoria.id == Producto.categoria_id)
        .join(Sucursal, Sucursal.id == Venta.sucursal_id)
        .filter(Sucursal.empresa_id == empresa_id, Venta.estado == "completada", dia <= _hoy())
        .group_by(dia, Venta.sucursal_id, Categoria.nombre)
        .all()
    )
    return pd.DataFrame(
        [{"fecha": f, "sucursal_id": s, "categoria": c, "unidades": float(u)} for f, s, c, u in filas],
        columns=["fecha", "sucursal_id", "categoria", "unidades"],
    )


def _rfm(db: Session, empresa_id: int) -> pd.DataFrame:
    """Recencia (días desde la última compra), frecuencia (compras) y monto (Bs) por cliente."""
    hoy = datetime.now(ZONA_HORARIA_LOCAL)
    filas = (
        db.query(
            Venta.cliente_id,
            func.max(Venta.creada_en),
            func.count(Venta.id),
            func.sum(Venta.total),
            # Sucursal "habitual": la de más compras (se resuelve abajo con mode).
            func.array_agg(Venta.sucursal_id),
        )
        .join(Sucursal, Sucursal.id == Venta.sucursal_id)
        .filter(Sucursal.empresa_id == empresa_id, Venta.estado == "completada", Venta.cliente_id.isnot(None))
        .group_by(Venta.cliente_id)
        .all()
    )
    datos = []
    for cliente_id, ultima, frecuencia, monto, sucursales in filas:
        datos.append({
            "cliente_id": cliente_id,
            "sucursal_id": max(set(sucursales), key=sucursales.count),
            "recencia": float(max(0, (hoy - ultima.astimezone(ZONA_HORARIA_LOCAL)).days)),
            "frecuencia": float(frecuencia),
            "monto": float(monto or 0),
        })
    return pd.DataFrame(datos, columns=["cliente_id", "sucursal_id", "recencia", "frecuencia", "monto"])


# ---------------------------------------------------------------- armado de resultados

def _serie(historico: pd.DataFrame, prediccion: pd.DataFrame, nombre: str) -> dict:
    """Histórico (últimos 30 días reales) + predicción (30 días) + comparación por categoría."""
    # El histórico termina ayer (hoy no se usa porque todavía no terminó): 30 días hasta ese día.
    ultimo = historico["fecha"].max() if not historico.empty else _hoy() - pd.Timedelta(days=1)
    desde = ultimo - pd.Timedelta(days=motor.HORIZONTE_DIAS - 1)
    hist = historico[historico["fecha"] >= desde]
    hist_dia = hist.groupby("fecha")["unidades"].sum()
    pred_dia = prediccion.groupby("fecha")["unidades"].sum()

    por_categoria = []
    for categoria in sorted(set(historico["categoria"]) | set(prediccion["categoria"])):
        antes = float(hist[hist["categoria"] == categoria]["unidades"].sum())
        despues = float(prediccion[prediccion["categoria"] == categoria]["unidades"].sum())
        por_categoria.append({
            "categoria": categoria,
            "ultimos_30": round(antes),
            "proximos_30": round(despues),
            "variacion_pct": round((despues - antes) / antes * 100, 1) if antes else None,
        })
    por_categoria.sort(key=lambda c: -c["proximos_30"])

    total_antes, total_despues = float(hist_dia.sum()), float(pred_dia.sum())
    return {
        "nombre": nombre,
        "historico": [{"fecha": f.isoformat(), "unidades": round(float(u), 1)} for f, u in hist_dia.items()],
        "prediccion": [{"fecha": f.isoformat(), "unidades": round(float(u), 1)} for f, u in pred_dia.items()],
        "ultimos_30": round(total_antes),
        "proximos_30": round(total_despues),
        "variacion_pct": round((total_despues - total_antes) / total_antes * 100, 1) if total_antes else None,
        "por_categoria": por_categoria,
        "interpretacion": _interpretar_demanda(total_antes, total_despues, por_categoria),
    }


def _interpretar_demanda(antes: float, despues: float, por_categoria: list[dict]) -> str:
    if not antes:
        return "No hay ventas recientes suficientes para comparar la demanda proyectada."
    variacion = (despues - antes) / antes * 100
    if abs(variacion) < 3:
        general = f"Se espera una demanda estable para los próximos 30 días (unas {round(despues)} unidades)."
    elif variacion > 0:
        general = f"Se espera un aumento de la demanda de alrededor del {variacion:.0f}% en los próximos 30 días."
    else:
        general = f"Se espera una baja de la demanda de alrededor del {abs(variacion):.0f}% en los próximos 30 días."
    con_variacion = [c for c in por_categoria if c["variacion_pct"] is not None and c["ultimos_30"] >= 5]
    if con_variacion:
        sube = max(con_variacion, key=lambda c: c["variacion_pct"])
        baja = min(con_variacion, key=lambda c: c["variacion_pct"])
        if sube["variacion_pct"] >= 5:
            general += f" La categoría {sube['categoria']} es la que más crecería ({sube['variacion_pct']:+.0f}%): conviene asegurar stock."
        if baja["variacion_pct"] <= -5 and baja is not sube:
            general += f" {baja['categoria']} bajaría ({baja['variacion_pct']:+.0f}%)."
    return general


def _interpretar_segmentos(segmentos: list[dict]) -> str:
    if not segmentos:
        return "Todavía no hay clientes con compras para segmentar."
    mejor = segmentos[0]
    texto = (
        f"El segmento {mejor['segmento']} reúne al {mejor['pct_clientes']:.0f}% de los clientes "
        f"y genera el {mejor['pct_ingresos']:.0f}% de los ingresos."
    )
    riesgo = next((s for s in segmentos if s["segmento"] == "En riesgo" and s["clientes"]), None)
    if riesgo:
        texto += (
            f" Hay {riesgo['clientes']} clientes en riesgo (sin comprar hace unos "
            f"{riesgo['recencia_media']:.0f} días en promedio): candidatos a una campaña de reactivación."
        )
    return texto


# ---------------------------------------------------------------- entrenamiento

def _ruta_modelo(empresa_id: int, tipo: str, version: int) -> str:
    carpeta = os.path.join(settings.uploads_dir, "modelos", f"empresa_{empresa_id}")
    os.makedirs(carpeta, exist_ok=True)
    return os.path.join(carpeta, f"{tipo}_v{version}.joblib")


def _siguiente_version(db: Session, empresa_id: int, tipo: str) -> int:
    actual = (
        db.query(func.max(models.ModeloML.version))
        .filter(models.ModeloML.empresa_id == empresa_id, models.ModeloML.tipo == tipo)
        .scalar()
    )
    return (actual or 0) + 1


def entrenar(db: Session, usuario: Usuario) -> dict:
    """Entrena los dos modelos de la empresa del usuario y guarda modelos, métricas y resultados."""
    empresa_id = usuario.empresa_id
    semilla = 1000 + empresa_id
    sucursales = {s.id: s.nombre for s in db.query(Sucursal).filter(Sucursal.empresa_id == empresa_id)}

    # --- supervisado: demanda ---
    # Hoy todavía no terminó: sus ventas parciales distorsionarían el entrenamiento y la evaluación.
    ayer = _hoy() - pd.Timedelta(days=1)
    diario = _ventas_diarias(db, empresa_id)
    diario = diario[diario["fecha"] <= ayer]
    try:
        demanda = motor.entrenar_demanda(diario, ayer, semilla)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    series = {TOTAL: _serie(demanda.historico, demanda.prediccion, "Todas las sucursales")}
    for sucursal_id in sorted(demanda.prediccion["sucursal_id"].unique()):
        series[str(int(sucursal_id))] = _serie(
            demanda.historico[demanda.historico["sucursal_id"] == sucursal_id],
            demanda.prediccion[demanda.prediccion["sucursal_id"] == sucursal_id],
            sucursales.get(int(sucursal_id), f"Sucursal {sucursal_id}"),
        )
    version = _siguiente_version(db, empresa_id, "demanda")
    archivo = _ruta_modelo(empresa_id, "demanda", version)
    joblib.dump({"modelo": demanda.modelo, "parametros": demanda.parametros}, archivo)
    db.add(models.ModeloML(
        empresa_id=empresa_id, tipo="demanda", algoritmo="RandomForestRegressor", version=version,
        metricas=demanda.metricas, parametros=demanda.parametros, resultado={"series": series},
        archivo=archivo, entrenado_por_id=usuario.id,
    ))

    # --- no supervisado: segmentación de clientes ---
    try:
        seg = motor.entrenar_segmentos(_rfm(db, empresa_id), semilla)
    except ValueError as exc:
        db.commit()  # el modelo de demanda ya quedó guardado
        raise HTTPException(status_code=400, detail=str(exc))
    por_sucursal = {}
    for sucursal_id, grupo in seg.asignacion.groupby("sucursal_id"):
        conteo = grupo["segmento"].value_counts()
        por_sucursal[str(int(sucursal_id))] = [
            {"segmento": s["segmento"], "clientes": int(conteo.get(s["segmento"], 0))} for s in seg.segmentos
        ]
    version = _siguiente_version(db, empresa_id, "segmentacion")
    archivo = _ruta_modelo(empresa_id, "segmentacion", version)
    joblib.dump({"modelo": seg.modelo, "escalador": seg.escalador, "parametros": seg.parametros}, archivo)
    db.add(models.ModeloML(
        empresa_id=empresa_id, tipo="segmentacion", algoritmo="KMeans", version=version,
        metricas=seg.metricas, parametros=seg.parametros,
        resultado={"segmentos": seg.segmentos, "por_sucursal": por_sucursal,
                   "interpretacion": _interpretar_segmentos(seg.segmentos)},
        archivo=archivo, entrenado_por_id=usuario.id,
    ))
    db.commit()
    return consultar(db, usuario, None)


# ---------------------------------------------------------------- consulta

def _ultimo(db: Session, empresa_id: int, tipo: str) -> models.ModeloML | None:
    return (
        db.query(models.ModeloML)
        .filter(models.ModeloML.empresa_id == empresa_id, models.ModeloML.tipo == tipo)
        .order_by(models.ModeloML.version.desc())
        .first()
    )


def _info_modelo(m: models.ModeloML) -> dict:
    return {"tipo": m.tipo, "algoritmo": m.algoritmo, "version": m.version,
            "metricas": m.metricas, "entrenado_en": m.entrenado_en}


def consultar(db: Session, usuario: Usuario, sucursal_id: int | None) -> dict:
    """Últimos resultados guardados de la empresa (opcionalmente de una sucursal)."""
    demanda = _ultimo(db, usuario.empresa_id, "demanda")
    segmentos = _ultimo(db, usuario.empresa_id, "segmentacion")
    respuesta = {"entrenado": bool(demanda and segmentos), "modelos": [], "demanda": None, "segmentos": None}

    if demanda:
        respuesta["modelos"].append(_info_modelo(demanda))
        series = demanda.resultado["series"]
        clave = str(sucursal_id) if sucursal_id is not None else TOTAL
        respuesta["demanda"] = series.get(clave)
    if segmentos:
        respuesta["modelos"].append(_info_modelo(segmentos))
        resultado = segmentos.resultado
        lista = resultado["segmentos"]
        if sucursal_id is not None:
            conteos = {s["segmento"]: s["clientes"] for s in resultado["por_sucursal"].get(str(sucursal_id), [])}
            lista = [{**s, "clientes": conteos.get(s["segmento"], 0)} for s in lista]
        respuesta["segmentos"] = {"segmentos": lista, "interpretacion": resultado["interpretacion"]}
    return respuesta
