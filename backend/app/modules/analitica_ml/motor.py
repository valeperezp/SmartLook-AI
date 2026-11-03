"""Motor de Machine Learning (CU15). No toca la base de datos: recibe DataFrames y devuelve resultados.

- Modelo supervisado: RandomForestRegressor que predice las unidades vendidas por día de
  cada serie (sucursal × categoría). Evaluado con MAE, RMSE y R² sobre los últimos días,
  que el modelo no ve al entrenar (validación temporal, no aleatoria).
- Modelo no supervisado: K-Means sobre recencia, frecuencia y monto (RFM) de cada cliente.
  k se elige entre 2 y 5 por el coeficiente de silueta.
- Datos sintéticos: si la historia real es corta, se completan días o clientes con el mismo
  patrón que los datos reales. Solo se usan para entrenar; nunca se muestran como reales.
"""
from dataclasses import dataclass
from datetime import date, timedelta

import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score, silhouette_score
from sklearn.preprocessing import StandardScaler

DIAS_MINIMOS_HISTORIA = 120
DIAS_PRUEBA = 14
HORIZONTE_DIAS = 30
CLIENTES_MINIMOS = 60
# Sin "fecha absoluta": un árbol no extrapola tendencias. Las variables van relativas al nivel
# reciente de cada serie (media de 28 días): así lo aprendido en una serie sirve para las otras,
# y "impulso" (media 7 / media 28) le dice al modelo si la serie viene subiendo o bajando.
FEATURES = [
    "sucursal_cod", "categoria_cod", "dia_semana", "nivel",
    "r_lag_1", "r_lag_7", "r_lag_14", "impulso", "r_mismo_dia",
]
VENTANA_FEATURES = 35  # días previos que necesita el cálculo de features (lag 28 + margen)


# ======================================================================
# Datos sintéticos
# ======================================================================

def completar_historia(diario: pd.DataFrame, semilla: int) -> tuple[pd.DataFrame, int]:
    """Agrega días sintéticos ANTES del primer día real hasta tener DIAS_MINIMOS_HISTORIA.

    Cada serie (sucursal, categoría) continúa hacia atrás su propia tendencia real (recta
    ajustada sobre los días reales) con su patrón por día de la semana y ruido de Poisson.
    Así los datos sintéticos no contradicen la tendencia que muestran los datos reales.
    """
    dias_reales = diario["fecha"].nunique()
    faltan = DIAS_MINIMOS_HISTORIA - dias_reales
    if faltan <= 0:
        return diario.assign(sintetico=False), 0

    rng = np.random.default_rng(semilla)
    primera = diario["fecha"].min()
    completo = _completar_calendario(diario.assign(sintetico=False), diario["fecha"].max())
    completo["x"] = (pd.to_datetime(completo["fecha"]) - pd.Timestamp(primera)).dt.days
    completo["dia_semana"] = pd.to_datetime(completo["fecha"]).dt.dayofweek
    filas = []
    for (sucursal_id, categoria), serie in completo.groupby(["sucursal_id", "categoria"]):
        media = max(float(serie["unidades"].mean()), 0.05)
        pendiente, ordenada = np.polyfit(serie["x"], serie["unidades"], 1)
        estacional = (serie.groupby("dia_semana")["unidades"].mean() / media).to_dict()
        for i in range(1, faltan + 1):
            dia = primera - timedelta(days=i)
            nivel = max(ordenada + pendiente * (-i), 0.2 * media)
            esperado = nivel * estacional.get(dia.weekday(), 1.0)
            filas.append({
                "fecha": dia, "sucursal_id": sucursal_id, "categoria": categoria,
                "unidades": float(rng.poisson(max(esperado, 0.05))),
            })
    sinteticos = pd.DataFrame(filas)
    combinado = pd.concat([sinteticos.assign(sintetico=True), diario.assign(sintetico=False)], ignore_index=True)
    return combinado.sort_values("fecha").reset_index(drop=True), len(sinteticos)


def completar_clientes(rfm: pd.DataFrame, semilla: int) -> tuple[pd.DataFrame, int]:
    """Agrega clientes sintéticos (remuestreando los reales con ruido) hasta CLIENTES_MINIMOS."""
    faltan = CLIENTES_MINIMOS - len(rfm)
    if faltan <= 0 or rfm.empty:
        return rfm.assign(sintetico=False), 0
    rng = np.random.default_rng(semilla)
    base = rfm.sample(n=faltan, replace=True, random_state=semilla).reset_index(drop=True)
    sinteticos = pd.DataFrame({
        "cliente_id": -np.arange(1, faltan + 1),
        "sucursal_id": base["sucursal_id"],
        "recencia": np.clip(base["recencia"] * rng.lognormal(0, 0.35, faltan), 0, None).round(),
        "frecuencia": np.clip(base["frecuencia"] * rng.lognormal(0, 0.35, faltan), 1, None).round(),
        "monto": np.clip(base["monto"] * rng.lognormal(0, 0.35, faltan), 1, None).round(2),
    })
    return pd.concat([rfm.assign(sintetico=False), sinteticos.assign(sintetico=True)], ignore_index=True), faltan


# ======================================================================
# Modelo supervisado: demanda
# ======================================================================

def _completar_calendario(diario: pd.DataFrame, hasta: date) -> pd.DataFrame:
    """Una fila por día y serie, con 0 donde no hubo ventas (el modelo necesita los ceros)."""
    fechas = pd.date_range(diario["fecha"].min(), hasta, freq="D").date
    series = diario[["sucursal_id", "categoria"]].drop_duplicates()
    grilla = series.merge(pd.DataFrame({"fecha": fechas}), how="cross")
    completo = grilla.merge(diario, on=["sucursal_id", "categoria", "fecha"], how="left")
    completo["unidades"] = completo["unidades"].fillna(0.0)
    completo["sintetico"] = completo["sintetico"].astype("boolean").fillna(False).astype(bool)
    return completo


def _features(df: pd.DataFrame, codigos_suc: dict, codigos_cat: dict) -> pd.DataFrame:
    df = df.sort_values(["sucursal_id", "categoria", "fecha"]).copy()
    df["sucursal_cod"] = df["sucursal_id"].map(codigos_suc)
    df["categoria_cod"] = df["categoria"].map(codigos_cat)
    df["dia_semana"] = pd.to_datetime(df["fecha"]).dt.dayofweek
    grupo = df.groupby(["sucursal_id", "categoria"])["unidades"]
    df["lag_1"] = grupo.shift(1)
    df["lag_7"] = grupo.shift(7)
    df["lag_14"] = grupo.shift(14)
    df["media_7"] = grupo.transform(lambda s: s.shift(1).rolling(7).mean())
    df["media_28"] = grupo.transform(lambda s: s.shift(1).rolling(28).mean())
    # Promedio del mismo día de la semana en las 4 semanas anteriores (captura el patrón semanal).
    df["media_mismo_dia"] = (df["lag_7"] + df["lag_14"] + grupo.shift(21) + grupo.shift(28)) / 4
    df["nivel"] = df["media_28"] + 0.5  # +0.5 evita dividir por cero en series casi sin ventas
    for col in ("lag_1", "lag_7", "lag_14", "mismo_dia"):
        origen = "media_mismo_dia" if col == "mismo_dia" else col
        df[f"r_{col}"] = df[origen] / df["nivel"]
    df["impulso"] = (df["media_7"] + 0.5) / df["nivel"]
    return df


def _predecir(modelo: RandomForestRegressor, filas: pd.DataFrame) -> np.ndarray:
    """El modelo predice unidades relativas al nivel de la serie; se vuelve a unidades."""
    return np.clip(modelo.predict(filas[FEATURES]) * filas["nivel"].to_numpy(), 0, None)


@dataclass
class ResultadoDemanda:
    modelo: RandomForestRegressor
    metricas: dict
    parametros: dict
    historico: pd.DataFrame  # solo días reales: fecha, sucursal_id, categoria, unidades
    prediccion: pd.DataFrame  # fecha, sucursal_id, categoria, unidades


def entrenar_demanda(diario_real: pd.DataFrame, hoy: date, semilla: int) -> ResultadoDemanda:
    """diario_real: columnas fecha (date), sucursal_id, categoria, unidades (ventas reales)."""
    if diario_real.empty:
        raise ValueError("No hay ventas registradas para entrenar el modelo de demanda")

    historia, n_sinteticos = completar_historia(diario_real, semilla)
    completo = _completar_calendario(historia, hoy)
    codigos_suc = {s: i for i, s in enumerate(sorted(completo["sucursal_id"].unique()))}
    codigos_cat = {c: i for i, c in enumerate(sorted(completo["categoria"].unique()))}
    datos = _features(completo, codigos_suc, codigos_cat).dropna(subset=FEATURES)

    # Validación temporal: se entrena con el pasado y se evalúa en los últimos días.
    corte = hoy - timedelta(days=DIAS_PRUEBA)
    entrenamiento = datos[datos["fecha"] <= corte]
    prueba = datos[(datos["fecha"] > corte) & (~datos["sintetico"])]
    parametros = {"n_estimators": 300, "min_samples_leaf": 5, "max_features": 0.7, "random_state": semilla, "n_jobs": -1}
    evaluador = RandomForestRegressor(**parametros).fit(
        entrenamiento[FEATURES], entrenamiento["unidades"] / entrenamiento["nivel"]
    )
    esperado, predicho = prueba["unidades"], _predecir(evaluador, prueba)
    # Error a nivel diario agregado por empresa: es lo que se grafica en el dashboard.
    por_dia = prueba.assign(pred=predicho).groupby("fecha")[["unidades", "pred"]].sum()

    metricas = {
        "mae": round(float(mean_absolute_error(esperado, predicho)), 3),
        "rmse": round(float(np.sqrt(mean_squared_error(esperado, predicho))), 3),
        "r2": round(float(r2_score(esperado, predicho)), 3),
        "mae_diario_total": round(float(mean_absolute_error(por_dia["unidades"], por_dia["pred"])), 2),
        "r2_diario_total": round(float(r2_score(por_dia["unidades"], por_dia["pred"])), 3) if len(por_dia) > 1 else None,
        "n_entrenamiento": int(len(entrenamiento)),
        "n_prueba": int(len(prueba)),
        "dias_prueba": DIAS_PRUEBA,
        "dias_reales": int(diario_real["fecha"].nunique()),
        "filas_sinteticas": int(n_sinteticos),
        "series": int(len(codigos_suc) * len(codigos_cat)),
        "importancia": {
            f: round(float(v), 3)
            for f, v in sorted(zip(FEATURES, evaluador.feature_importances_), key=lambda x: -x[1])
        },
    }

    # Modelo final: se reentrena con todo y se proyecta día a día (cada predicción alimenta los lags).
    modelo = RandomForestRegressor(**parametros).fit(datos[FEATURES], datos["unidades"] / datos["nivel"])
    actual = completo[["fecha", "sucursal_id", "categoria", "unidades", "sintetico"]].copy()
    proyectado = []
    for paso in range(1, HORIZONTE_DIAS + 1):
        dia = hoy + timedelta(days=paso)
        nuevas = actual[["sucursal_id", "categoria"]].drop_duplicates().assign(fecha=dia, unidades=np.nan, sintetico=False)
        ventana = pd.concat([actual[actual["fecha"] > dia - timedelta(days=VENTANA_FEATURES)], nuevas], ignore_index=True)
        feats = _features(ventana, codigos_suc, codigos_cat)
        filas_dia = feats[feats["fecha"] == dia]
        valores = _predecir(modelo, filas_dia)
        nuevas = filas_dia[["fecha", "sucursal_id", "categoria"]].assign(unidades=valores, sintetico=False)
        actual = pd.concat([actual, nuevas], ignore_index=True)
        proyectado.append(nuevas)

    return ResultadoDemanda(
        modelo=modelo,
        metricas=metricas,
        parametros={**parametros, "features": FEATURES, "horizonte_dias": HORIZONTE_DIAS,
                    "codigos_sucursal": {str(k): v for k, v in codigos_suc.items()}, "codigos_categoria": codigos_cat},
        historico=completo[~completo["sintetico"]][["fecha", "sucursal_id", "categoria", "unidades"]],
        prediccion=pd.concat(proyectado, ignore_index=True)[["fecha", "sucursal_id", "categoria", "unidades"]],
    )


# ======================================================================
# Modelo no supervisado: segmentación RFM
# ======================================================================

NOMBRES_SEGMENTOS = {
    2: ["Frecuentes", "Ocasionales"],
    3: ["VIP", "Regulares", "En riesgo"],
    4: ["VIP", "Leales", "Ocasionales", "En riesgo"],
    5: ["VIP", "Leales", "Regulares", "Ocasionales", "En riesgo"],
}

DESCRIPCIONES = {
    "VIP": "Compran seguido, gastan mucho y compraron hace poco. Cuidalos con beneficios exclusivos.",
    "Frecuentes": "Compran seguido y hace poco. Son la base de las ventas recurrentes.",
    "Leales": "Compran con regularidad y un gasto alto. Buen público para lanzamientos.",
    "Regulares": "Compran de vez en cuando con un gasto medio. Se pueden activar con promociones.",
    "Ocasionales": "Pocas compras y gasto bajo. Responden a ofertas puntuales.",
    "En riesgo": "Hace tiempo que no compran. Conviene una campaña de reactivación.",
}


@dataclass
class ResultadoSegmentos:
    modelo: KMeans
    escalador: StandardScaler
    metricas: dict
    parametros: dict
    asignacion: pd.DataFrame  # clientes reales con su segmento
    segmentos: list[dict]


def _matriz_rfm(rfm: pd.DataFrame) -> np.ndarray:
    # Logaritmo en frecuencia y monto: suelen tener colas largas que dominarían la distancia.
    return np.column_stack([rfm["recencia"], np.log1p(rfm["frecuencia"]), np.log1p(rfm["monto"])])


def entrenar_segmentos(rfm_real: pd.DataFrame, semilla: int) -> ResultadoSegmentos:
    """rfm_real: cliente_id, sucursal_id, recencia (días), frecuencia (compras), monto (Bs)."""
    if len(rfm_real) < 3:
        raise ValueError("Se necesitan al menos 3 clientes con compras para segmentar")

    datos, n_sinteticos = completar_clientes(rfm_real, semilla)
    escalador = StandardScaler().fit(_matriz_rfm(datos))
    x = escalador.transform(_matriz_rfm(datos))

    candidatos = {}
    for k in range(2, min(5, len(datos) - 1) + 1):
        km = KMeans(n_clusters=k, n_init=10, random_state=semilla).fit(x)
        candidatos[k] = (silhouette_score(x, km.labels_), km)
    k, (silueta, modelo) = max(candidatos.items(), key=lambda par: par[1][0])

    # Orden de los segmentos: mejor cliente = más frecuencia y monto, menos recencia (z-scores del centroide).
    centro = modelo.cluster_centers_
    puntaje = centro[:, 1] + centro[:, 2] - centro[:, 0]
    orden = np.argsort(-puntaje)
    nombre_de = {int(cluster): NOMBRES_SEGMENTOS[k][pos] for pos, cluster in enumerate(orden)}

    reales = datos[~datos["sintetico"]].copy()
    reales["cluster"] = modelo.predict(escalador.transform(_matriz_rfm(reales)))
    reales["segmento"] = reales["cluster"].map(nombre_de)
    total_clientes, total_monto = len(reales), float(reales["monto"].sum()) or 1.0

    segmentos = []
    for cluster in orden:
        grupo = reales[reales["cluster"] == cluster]
        nombre = nombre_de[int(cluster)]
        segmentos.append({
            "segmento": nombre,
            "clientes": int(len(grupo)),
            "pct_clientes": round(len(grupo) / total_clientes * 100, 1) if total_clientes else 0.0,
            "pct_ingresos": round(float(grupo["monto"].sum()) / total_monto * 100, 1),
            "recencia_media": round(float(grupo["recencia"].mean()), 1) if len(grupo) else None,
            "frecuencia_media": round(float(grupo["frecuencia"].mean()), 1) if len(grupo) else None,
            "monto_medio": round(float(grupo["monto"].mean()), 2) if len(grupo) else None,
            "descripcion": DESCRIPCIONES[nombre],
        })

    return ResultadoSegmentos(
        modelo=modelo,
        escalador=escalador,
        metricas={
            "silueta": round(float(silueta), 3),
            "k": int(k),
            "silueta_por_k": {str(kk): round(float(v[0]), 3) for kk, v in candidatos.items()},
            "inercia": round(float(modelo.inertia_), 2),
            "clientes_reales": int(total_clientes),
            "clientes_sinteticos": int(n_sinteticos),
        },
        parametros={"algoritmo": "KMeans", "n_init": 10, "random_state": semilla,
                    "variables": ["recencia", "log1p(frecuencia)", "log1p(monto)"], "escalado": "StandardScaler"},
        asignacion=reales[["cliente_id", "sucursal_id", "segmento"]],
        segmentos=segmentos,
    )
