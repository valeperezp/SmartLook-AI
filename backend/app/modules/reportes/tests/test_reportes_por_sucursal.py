"""CU14 — Reportes generativos por sucursal, estimaciones del modelo de ML y conversación.

Cubre el pedido "los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal":
- el top se calcula DENTRO de cada sucursal (no es un top general filtrado),
- nunca entran ventas de otra empresa,
- la respuesta trae un bloque por sucursal (un gráfico cada una) y un resumen en lenguaje natural,
- la conversación continúa ("ahora solo Centro", "mostralo en torta", "¿y la estimación?"),
- las estimaciones salen del modelo de ML entrenado y exigen un plan que lo incluya (RN-05).

Usa SQLite en memoria (no toca ninguna base real) y una IA simulada (respuestas fijas).
Ejecutar desde `backend/`:  python -m pytest app/modules/reportes/tests -v
"""
from datetime import date, datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import app.main  # noqa: F401  registra todos los modelos
from app.modules.analitica_ml.models import ModeloML
from app.modules.catalogo.models import Categoria, Producto
from app.modules.empresas.models import Empresa
from app.modules.reportes import catalogo_reportes as catalogo
from app.modules.reportes import generativo
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.db.session import Base

HACE_UNA_SEMANA = datetime.now() - timedelta(days=7)


@pytest.fixture()
def db():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)()
    yield sesion
    sesion.close()
    engine.dispose()


@pytest.fixture()
def datos(db):
    """Empresa con Centro y Norte (cada una con un líder distinto) y otra empresa que vende mucho más."""
    propia, ajena = Empresa(nombre="SmartLook", slug="smartlook-t"), Empresa(nombre="Otra", slug="otra-t")
    db.add_all([propia, ajena])
    db.flush()
    centro = Sucursal(empresa_id=propia.id, nombre="Centro", direccion="a")
    norte = Sucursal(empresa_id=propia.id, nombre="Norte", direccion="b")
    equipetrol = Sucursal(empresa_id=propia.id, nombre="Equipetrol", direccion="c")  # sin ventas
    suc_ajena = Sucursal(empresa_id=ajena.id, nombre="Centro Ajeno", direccion="d")
    cat = Categoria(empresa_id=propia.id, nombre="Camisas")
    cat_ajena = Categoria(empresa_id=ajena.id, nombre="Camisas")
    db.add_all([centro, norte, equipetrol, suc_ajena, cat, cat_ajena])
    db.flush()
    camisa = Producto(empresa_id=propia.id, nombre="Camisa", precio=100, categoria_id=cat.id)
    jean = Producto(empresa_id=propia.id, nombre="Jean", precio=200, categoria_id=cat.id)
    chaqueta = Producto(empresa_id=propia.id, nombre="Chaqueta", precio=300, categoria_id=cat.id)
    producto_ajeno = Producto(empresa_id=ajena.id, nombre="Producto Ajeno", precio=50, categoria_id=cat_ajena.id)
    admin = Usuario(nombre="Admin", email="admin@t.bo", rol="administrador", empresa_id=propia.id)
    db.add_all([camisa, jean, chaqueta, producto_ajeno, admin])
    db.flush()

    def vender(sucursal, producto, cantidad):
        venta = Venta(sucursal_id=sucursal.id, estado="completada", total=producto.precio * cantidad,
                      creada_en=HACE_UNA_SEMANA)
        db.add(venta)
        db.flush()
        db.add(VentaItem(venta_id=venta.id, producto_id=producto.id, cantidad=cantidad, precio_unitario=producto.precio))

    vender(centro, camisa, 10)   # Centro: Camisa > Jean > Chaqueta
    vender(centro, jean, 4)
    vender(centro, chaqueta, 1)
    vender(norte, jean, 7)       # Norte: Jean > Camisa
    vender(norte, camisa, 2)
    vender(suc_ajena, producto_ajeno, 500)  # otra empresa: nunca debe aparecer
    db.commit()
    return {"empresa": propia, "centro": centro, "norte": norte, "equipetrol": equipetrol, "admin": admin}


def _filtros(datos, **extra) -> catalogo.Filtros:
    hoy = date.today()
    return catalogo.Filtros(empresa_id=datos["empresa"].id, fecha_inicio=hoy - timedelta(days=89), fecha_fin=hoy, **extra)


# ---------------------------------------------------------------------------------------------------------------
# "Top N agrupado por sucursal": el ranking es de cada sucursal y solo de la empresa del usuario
# ---------------------------------------------------------------------------------------------------------------

def test_el_top_se_calcula_dentro_de_cada_sucursal(db, datos):
    filas = catalogo.productos_por_sucursal(db, _filtros(datos, limite=1))
    assert [(f["sucursal"], f["etiqueta"], f["unidades"]) for f in filas] == [
        ("Centro", "Camisa", 10),  # Centro vendió 15 en total: va primero
        ("Norte", "Jean", 7),      # el líder de Norte NO es el líder general
    ]


def test_el_limite_aplica_a_cada_sucursal_y_no_entran_ventas_de_otra_empresa(db, datos):
    filas = catalogo.productos_por_sucursal(db, _filtros(datos, limite=10))
    assert {f["sucursal"] for f in filas} == {"Centro", "Norte"}
    assert len([f for f in filas if f["sucursal"] == "Centro"]) == 3
    assert all(f["etiqueta"] != "Producto Ajeno" for f in filas)


def test_la_respuesta_trae_un_grafico_por_sucursal_un_resumen_y_las_sucursales_sin_ventas(db, datos):
    hoy = date.today()
    r = generativo.ejecutar(db, datos["admin"], {
        "tipo": "productos_por_sucursal", "fecha_inicio": (hoy - timedelta(days=89)).isoformat(),
        "fecha_fin": hoy.isoformat(), "limite": 10,
    }, "los 10 productos más vendidos de los últimos 3 meses agrupados por sucursal", "ia", guardar=False)
    assert r["estado"] == "ok"
    assert [g["nombre"] for g in r["grupos"]] == ["Centro", "Norte"]
    assert r["grupos"][1]["puntos"][0] == {"etiqueta": "Jean", "valor": 7.0}
    assert r["sucursales_sin_datos"] == ["Equipetrol"]
    assert "En Centro, lo más vendido fue Camisa (10 u.)" in r["resumen"]
    assert "En Norte, lo más vendido fue Jean (7 u.)" in r["resumen"]
    assert "Sin ventas en el período: Equipetrol" in r["resumen"]
    assert r["sugerencias"]  # siempre propone cómo seguir la conversación


# ---------------------------------------------------------------------------------------------------------------
# Interpretación: reglas que corrigen al modelo y conversación sobre el reporte anterior
# ---------------------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("frase, tipo_ia, esperado", [
    ("los 10 productos más vendidos agrupados por sucursal", "ventas_por_producto", "productos_por_sucursal"),
    ("productos mas vendidos por sucursal", "ventas_por_sucursal", "productos_por_sucursal"),
    ("como evolucionaron las ventas en cada sucursal", "ventas_por_dia", "evolucion_por_sucursal"),
    ("cuanto vamos a vender el proximo mes", "ventas_por_dia", "prediccion_demanda"),
    ("estimacion de demanda por sucursal", "prediccion_demanda", "prediccion_por_sucursal"),
    ("las ventas de septiembre por sucursal", "ventas_por_sucursal", "ventas_por_sucursal"),  # sin cambios
])
def test_las_reglas_corrigen_el_tipo_que_eligio_la_ia(frase, tipo_ia, esperado):
    intencion = {"tipo": tipo_ia}
    generativo._aplicar_reglas(intencion, generativo._normalizar(frase), None)
    assert intencion["tipo"] == esperado


def test_y_la_estimacion_despues_de_un_reporte_por_sucursal_sigue_por_sucursal():
    intencion = {"tipo": "prediccion_demanda"}
    generativo._aplicar_reglas(intencion, generativo._normalizar("¿y la estimación?"), {"tipo": "productos_por_sucursal"})
    assert intencion["tipo"] == "prediccion_por_sucursal"


def test_pedir_el_grafico_por_su_nombre_lo_cambia():
    intencion = {"tipo": "productos_por_sucursal", "grafico": "barras"}
    generativo._aplicar_reglas(intencion, generativo._normalizar("mostralo en torta"), None)
    assert intencion["grafico"] == "torta"


def test_la_conversacion_conserva_lo_anterior_y_descarta_nombres_inventados(db, datos, monkeypatch):
    previo = generativo._previo(db, datos["admin"], {
        "tipo": "productos_por_sucursal", "fecha_inicio": "2026-08-01", "fecha_fin": "2026-10-30",
        "sucursal_ids": [datos["centro"].id], "limite": 10,
    })
    assert previo["sucursales"] == ["Centro"]
    # El modelo copia el reporte anterior, cambia el gráfico… e inventa una sucursal que nadie nombró.
    monkeypatch.setattr(generativo.ia_service, "interpretar_json", lambda db_, prompt, frase: {
        "tipo": "productos_por_sucursal", "fecha_inicio": "2026-08-01", "fecha_fin": "2026-10-30",
        "sucursales": ["Centro", "Sopocachi"], "categorias": [], "productos": [], "limite": 10, "grafico": "torta",
    })
    intencion = generativo._interpretar(db, "mostralo en torta", previo)
    assert intencion["sucursales"] == ["Centro"]  # se conserva la de la charla; la inventada se descarta
    assert intencion["grafico"] == "torta"


def test_un_contexto_de_otra_empresa_no_aporta_nombres(db, datos):
    ajena = db.query(Sucursal).filter(Sucursal.nombre == "Centro Ajeno").one()
    previo = generativo._previo(db, datos["admin"], {"tipo": "productos_por_sucursal", "sucursal_ids": [ajena.id]})
    assert previo["sucursales"] == []


# ---------------------------------------------------------------------------------------------------------------
# Estimaciones: salen del modelo de ML entrenado (CU15) y respetan el plan (RN-05)
# ---------------------------------------------------------------------------------------------------------------

def _guardar_modelo(db, datos):
    serie = lambda cats: {"por_categoria": [{"categoria": c, "ultimos_30": a, "proximos_30": p} for c, a, p in cats]}
    db.add(ModeloML(
        empresa_id=datos["empresa"].id, tipo="demanda", algoritmo="RandomForestRegressor", version=1,
        metricas={}, parametros={}, archivo="x.joblib",
        resultado={"series": {
            "total": serie([("Camisas", 20, 30), ("Jeans", 10, 5)]),
            str(datos["centro"].id): serie([("Camisas", 15, 24)]),
            str(datos["norte"].id): serie([("Jeans", 10, 5)]),
        }},
    ))
    db.commit()


def test_sin_modelo_entrenado_la_estimacion_avisa_en_vez_de_inventar(db, datos):
    with pytest.raises(catalogo.SinModeloEntrenado):
        catalogo.prediccion_demanda(db, _filtros(datos))


def test_la_estimacion_por_sucursal_usa_el_modelo_de_cada_sucursal(db, datos):
    _guardar_modelo(db, datos)
    filas = catalogo.prediccion_por_sucursal(db, _filtros(datos))
    assert [(f["sucursal"], f["etiqueta"], f["proximos_30"], f["variacion_pct"]) for f in filas] == [
        ("Centro", "Camisas", 24.0, 60.0),
        ("Norte", "Jeans", 5.0, -50.0),
    ]


def test_las_estimaciones_exigen_un_plan_con_analitica(db, datos):
    _guardar_modelo(db, datos)
    with pytest.raises(HTTPException) as error:  # la empresa de prueba no tiene suscripción con ML
        generativo.ejecutar(db, datos["admin"], {"tipo": "prediccion_demanda"}, None, "manual", guardar=False)
    assert error.value.status_code == 403
