"""CU11 — Cambios y devoluciones: el plazo de 7 días y las cantidades las valida el SERVIDOR.

- Plazo: una venta de hace más de 7 días (o de los días que configure la empresa) se rechaza con 400
  "El plazo para cambios ha vencido" y no se toca el inventario.
- Cantidades: no se puede devolver más de lo vendido, descontando lo ya devuelto.
- Cambio: lo devuelto vuelve al inventario y lo nuevo se descuenta; si falta stock no queda nada a medias.
- Sincronización móvil: usa las mismas reglas; el plazo se mide con la fecha en que el dispositivo hizo la devolución.

Usa SQLite en memoria (no toca ninguna base real). Ejecutar desde `backend/`:  python -m pytest app/modules -v
"""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.modules.auth.service import get_current_user
from app.modules.catalogo.models import Categoria, Color, Producto, Talla
from app.modules.empresas.models import Empresa
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import Devolucion
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta
from app.shared.db.session import Base, get_db

MENSAJE_PLAZO = "El plazo para cambios ha vencido"
STOCK = 10


class Entorno:
    def __init__(self, client, Sesion, ids, actual):
        self.http, self.Sesion, self.ids, self._actual = client, Sesion, ids, actual

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def stock(self, que: str) -> int:
        with self.Sesion() as db:
            return db.get(Inventario, self.ids[f"inv_{que}"]).cantidad_disponible

    def contar(self, modelo) -> int:
        with self.Sesion() as db:
            return db.query(modelo).count()

    def item(self, producto: str = "camisa", talla: str = "M", cantidad: int = 1):
        return {"producto_id": self.ids[producto], "talla_id": self.ids[f"talla_{talla}"], "color_id": self.ids["color"], "cantidad": cantidad}

    def vender(self, cantidad: int = 2, talla: str = "M", dias_atras: float = 0) -> int:
        """Una venta presencial completada en la sucursal A; [dias_atras] la envejece."""
        self.como("cajero")
        r = self.http.post("/ventas", json={"sucursal_id": self.ids["suc_a"], "items": [self.item("camisa", talla, cantidad)]})
        assert r.status_code == 201, r.text
        venta_id = r.json()["id"]
        if dias_atras:
            self.envejecer(venta_id, dias_atras)
        return venta_id

    def envejecer(self, venta_id: int, dias: float):
        with self.Sesion() as db:
            db.get(Venta, venta_id).creada_en = datetime.now(timezone.utc) - timedelta(days=dias)
            db.commit()

    def devolver(self, venta_id: int, items_devueltos, items_nuevos=None, tipo="devolucion", quien="cajero", **extra):
        self.como(quien)
        cuerpo = {"venta_id": venta_id, "tipo": tipo, "items_devueltos": items_devueltos, "items_nuevos": items_nuevos or [], **extra}
        return self.http.post("/devoluciones", json=cuerpo)


@pytest.fixture()
def entorno():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = Sesion()
    empresa, otra = Empresa(nombre="Tienda", slug="tienda"), Empresa(nombre="Otra", slug="otra")
    db.add_all([empresa, otra])
    db.flush()
    suc_a = Sucursal(empresa_id=empresa.id, nombre="Centro", direccion="Av. 1")
    suc_b = Sucursal(empresa_id=empresa.id, nombre="Norte", direccion="Av. 2")
    suc_otra = Sucursal(empresa_id=otra.id, nombre="Ajena", direccion="Av. 9")
    cat = Categoria(empresa_id=empresa.id, nombre="Ropa")
    t_m, t_l = Talla(empresa_id=empresa.id, nombre="M"), Talla(empresa_id=empresa.id, nombre="L")
    color = Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([suc_a, suc_b, suc_otra, cat, t_m, t_l, color])
    db.flush()
    camisa = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=cat.id)
    polo = Producto(empresa_id=empresa.id, nombre="Polo", precio=50, categoria_id=cat.id)
    usuarios = {
        "cajero": Usuario(nombre="Cajero A", email="a@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "cajero_b": Usuario(nombre="Cajero B", email="b@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_b.id),
        "encargado": Usuario(nombre="Encargado A", email="e@t.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "admin": Usuario(nombre="Admin", email="ad@t.bo", rol="administrador", empresa_id=empresa.id),
        "admin_ajeno": Usuario(nombre="Admin Ajeno", email="x@o.bo", rol="administrador", empresa_id=otra.id),
        "cliente": Usuario(nombre="Cliente", email="c@t.bo", rol="cliente", empresa_id=empresa.id),
    }
    db.add_all([camisa, polo, *usuarios.values()])
    db.flush()
    inv = {
        "camisa_M": Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=t_m.id, color_id=color.id, cantidad_disponible=STOCK),
        "camisa_L": Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=t_l.id, color_id=color.id, cantidad_disponible=STOCK),
        "polo_M": Inventario(producto_id=polo.id, sucursal_id=suc_a.id, talla_id=t_m.id, color_id=color.id, cantidad_disponible=STOCK),
    }
    db.add_all(inv.values())
    db.commit()
    ids = {
        "suc_a": suc_a.id, "suc_b": suc_b.id, "camisa": camisa.id, "polo": polo.id, "talla_M": t_m.id, "talla_L": t_l.id, "color": color.id,
        **{f"inv_{k}": v.id for k, v in inv.items()}, **{k: u.id for k, u in usuarios.items()},
    }
    db.close()

    actual = {"id": ids["cajero"]}

    def _db():
        sesion = Sesion()
        try:
            yield sesion
        finally:
            sesion.close()

    def _usuario():
        with Sesion() as sesion:
            u = sesion.get(Usuario, actual["id"])
            sesion.expunge(u)
            return u

    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_current_user] = _usuario
    try:
        yield Entorno(TestClient(app), Sesion, ids, actual)
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


# ---------------------------------------------------------------------------------------------------------------
# Plazo de 7 días (lo valida el backend)
# ---------------------------------------------------------------------------------------------------------------

def test_una_venta_dentro_del_plazo_se_devuelve_y_el_stock_vuelve(entorno):
    venta_id = entorno.vender(cantidad=2, dias_atras=6)
    assert entorno.stock("camisa_M") == STOCK - 2

    r = entorno.devolver(venta_id, [entorno.item(cantidad=1)])

    assert r.status_code == 201, r.text
    cuerpo = r.json()
    assert (cuerpo["tipo"], cuerpo["total_devuelto"], cuerpo["total_nuevo"], cuerpo["diferencia"]) == ("devolucion", 100.0, 0.0, -100.0)  # solo reembolso: se le devuelven los 100
    assert entorno.stock("camisa_M") == STOCK - 1


def test_una_venta_de_hace_8_dias_se_rechaza_por_plazo_vencido_y_no_toca_el_inventario(entorno):
    venta_id = entorno.vender(cantidad=2, dias_atras=8)

    r = entorno.devolver(venta_id, [entorno.item(cantidad=1)])

    assert r.status_code == 400
    assert r.json()["detail"] == MENSAJE_PLAZO
    assert entorno.stock("camisa_M") == STOCK - 2  # sin cambios
    assert entorno.contar(Devolucion) == 0
    assert entorno.contar(MovimientoInventario) == 1  # solo el de la venta


def test_el_plazo_lo_mide_el_servidor_aunque_el_cliente_mienta_con_la_fecha(entorno):
    """La web no manda fecha: el servidor usa su reloj. Un campo `fecha` extra se ignora."""
    venta_id = entorno.vender(cantidad=2, dias_atras=9)

    r = entorno.devolver(venta_id, [entorno.item()], fecha=datetime.now(timezone.utc).isoformat())

    assert r.status_code == 400 and r.json()["detail"] == MENSAJE_PLAZO


def test_el_plazo_es_configurable_por_empresa(entorno):
    assert (entorno.como("cajero"), entorno.http.get("/devoluciones/configuracion").json())[1] == {"plazo_dias": 7}
    venta_id = entorno.vender(dias_atras=4)
    assert entorno.devolver(venta_id, [entorno.item()], tipo="devolucion").status_code == 201  # 4 días: dentro de los 7

    entorno.como("admin")
    assert entorno.http.put("/devoluciones/configuracion", json={"plazo_dias": 3}).json() == {"plazo_dias": 3}
    otra = entorno.vender(dias_atras=4)  # ahora el plazo es de 3 días

    r = entorno.devolver(otra, [entorno.item()])

    assert r.status_code == 400 and r.json()["detail"] == MENSAJE_PLAZO


def test_solo_el_administrador_cambia_el_plazo(entorno):
    entorno.como("cajero")
    assert entorno.http.put("/devoluciones/configuracion", json={"plazo_dias": 30}).status_code == 403
    entorno.como("admin")
    assert entorno.http.put("/devoluciones/configuracion", json={"plazo_dias": 0}).status_code == 422


# ---------------------------------------------------------------------------------------------------------------
# Cantidades
# ---------------------------------------------------------------------------------------------------------------

def test_no_se_puede_devolver_mas_de_lo_comprado(entorno):
    venta_id = entorno.vender(cantidad=2)

    r = entorno.devolver(venta_id, [entorno.item(cantidad=3)])

    assert r.status_code == 400 and "solo se pueden devolver 2" in r.json()["detail"]
    assert entorno.stock("camisa_M") == STOCK - 2


def test_se_descuentan_las_devoluciones_previas(entorno):
    venta_id = entorno.vender(cantidad=2)
    assert entorno.devolver(venta_id, [entorno.item(cantidad=1)]).status_code == 201

    exceso = entorno.devolver(venta_id, [entorno.item(cantidad=2)])
    resto = entorno.devolver(venta_id, [entorno.item(cantidad=1)])
    de_mas = entorno.devolver(venta_id, [entorno.item(cantidad=1)])

    assert exceso.status_code == 400 and "solo se pueden devolver 1" in exceso.json()["detail"]
    assert resto.status_code == 201
    assert de_mas.status_code == 400 and "solo se pueden devolver 0" in de_mas.json()["detail"]
    assert entorno.stock("camisa_M") == STOCK  # todo volvió


def test_una_prenda_que_no_era_de_la_venta_se_rechaza(entorno):
    venta_id = entorno.vender(cantidad=1)

    r = entorno.devolver(venta_id, [entorno.item("polo", "M", 1)])

    assert r.status_code == 400 and "no pertenece a la venta original" in r.json()["detail"]


# ---------------------------------------------------------------------------------------------------------------
# Cambio y devolución
# ---------------------------------------------------------------------------------------------------------------

def test_un_cambio_devuelve_lo_viejo_y_descuenta_lo_nuevo(entorno):
    venta_id = entorno.vender(cantidad=1, talla="M")

    r = entorno.devolver(venta_id, [entorno.item("camisa", "M")], [entorno.item("camisa", "L")], tipo="cambio", motivo="no le quedó")

    assert r.status_code == 201, r.text
    assert entorno.stock("camisa_M") == STOCK  # la M volvió
    assert entorno.stock("camisa_L") == STOCK - 1  # la L salió
    cuerpo = r.json()
    assert (cuerpo["total_devuelto"], cuerpo["total_nuevo"], cuerpo["diferencia"]) == (100.0, 100.0, 0.0)
    assert sorted((i["tipo_item"], i["nombre_talla"]) for i in cuerpo["items"]) == [("devuelto", "M"), ("nuevo", "L")]


def test_un_cambio_por_algo_mas_barato_devuelve_la_diferencia(entorno):
    venta_id = entorno.vender(cantidad=1)

    r = entorno.devolver(venta_id, [entorno.item()], [entorno.item("polo", "M")], tipo="cambio")

    assert r.json()["diferencia"] == -50.0  # lo nuevo cuesta 50 menos: se le devuelve


def test_un_cambio_sin_stock_de_lo_nuevo_falla_y_no_deja_nada_a_medias(entorno):
    venta_id = entorno.vender(cantidad=1)
    with entorno.Sesion() as db:
        db.get(Inventario, entorno.ids["inv_camisa_L"]).cantidad_disponible = 0
        db.commit()

    r = entorno.devolver(venta_id, [entorno.item("camisa", "M")], [entorno.item("camisa", "L")], tipo="cambio")

    assert r.status_code == 400 and "Stock insuficiente" in r.json()["detail"]
    assert entorno.stock("camisa_M") == STOCK - 1  # lo devuelto NO volvió al estante (se revirtió todo)
    assert entorno.contar(Devolucion) == 0


def test_los_tipos_se_validan(entorno):
    venta_id = entorno.vender(cantidad=1)

    assert entorno.devolver(venta_id, [entorno.item()], [entorno.item("polo", "M")], tipo="devolucion").status_code == 400
    assert entorno.devolver(venta_id, [entorno.item()], [], tipo="cambio").status_code == 400
    assert entorno.devolver(venta_id, [], tipo="devolucion").status_code == 422


def test_reintentar_con_el_mismo_uuid_no_duplica_la_devolucion(entorno):
    venta_id = entorno.vender(cantidad=2)

    a = entorno.devolver(venta_id, [entorno.item()], uuid="mi-devolucion-1")
    b = entorno.devolver(venta_id, [entorno.item()], uuid="mi-devolucion-1")

    assert a.status_code == b.status_code == 201 and a.json()["id"] == b.json()["id"]
    assert entorno.contar(Devolucion) == 1
    assert entorno.stock("camisa_M") == STOCK - 1  # se sumó una sola vez


# ---------------------------------------------------------------------------------------------------------------
# Permisos
# ---------------------------------------------------------------------------------------------------------------

def test_permisos_y_aislamiento_entre_sucursales_y_empresas(entorno):
    venta_id = entorno.vender(cantidad=1)

    assert entorno.devolver(venta_id, [entorno.item()], quien="cajero_b").status_code == 404  # otra sucursal
    assert entorno.devolver(venta_id, [entorno.item()], quien="admin_ajeno").status_code == 404  # otra empresa
    assert entorno.devolver(venta_id, [entorno.item()], quien="cliente").status_code == 403
    assert entorno.devolver(999999, [entorno.item()]).status_code == 404
    assert entorno.devolver(venta_id, [entorno.item()], quien="encargado").status_code == 201  # el encargado de la sucursal sí


# ---------------------------------------------------------------------------------------------------------------
# Búsqueda de la venta
# ---------------------------------------------------------------------------------------------------------------

def test_buscar_por_numero_de_ticket_muestra_lo_que_se_puede_devolver_y_el_plazo(entorno):
    venta_id = entorno.vender(cantidad=3, dias_atras=2)
    entorno.devolver(venta_id, [entorno.item(cantidad=1)])
    entorno.como("cajero")

    for q in (str(venta_id), f"#{venta_id}"):
        r = entorno.http.get("/devoluciones/buscar", params={"q": q})
        assert r.status_code == 200, r.text
        v = r.json()
        assert (v["venta_id"], v["total"], v["plazo_dias"], v["dias_transcurridos"], v["dentro_de_plazo"]) == (venta_id, 300.0, 7, 2, True)
        assert [(i["nombre_producto"], i["cantidad_vendida"], i["cantidad_devuelta"], i["cantidad_devolvible"]) for i in v["items"]] == [("Camisa Oxford", 3, 1, 2)]


def test_buscar_marca_las_ventas_fuera_de_plazo_pero_igual_las_muestra(entorno):
    venta_id = entorno.vender(cantidad=1, dias_atras=10)
    entorno.como("cajero")

    v = entorno.http.get("/devoluciones/buscar", params={"q": str(venta_id)}).json()

    assert (v["dias_transcurridos"], v["dentro_de_plazo"]) == (10, False)  # el aviso es informativo: decide el servidor al registrar


def test_buscar_por_uuid_o_recibo_de_una_venta_que_vino_de_la_app_movil(entorno):
    entorno.como("cajero")
    r = entorno.http.post("/sync/operaciones", json={"operaciones": [{
        "uuid": "abcd1234-5678-4abc-9def-0123456789ab", "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["suc_a"],
        "items": [entorno.item(cantidad=2)],
    }]})
    venta_id = r.json()["resultados"][0]["id_servidor"]

    for q in ("abcd1234-5678-4abc-9def-0123456789ab", "ABCD1234", "abcd12"):
        v = entorno.http.get("/devoluciones/buscar", params={"q": q}).json()
        assert (v["venta_id"], v["recibo"], v["uuid"]) == (venta_id, "ABCD1234", "abcd1234-5678-4abc-9def-0123456789ab")


def test_buscar_una_venta_inexistente_ajena_o_vacia(entorno):
    venta_id = entorno.vender(cantidad=1)

    entorno.como("cajero")
    assert entorno.http.get("/devoluciones/buscar", params={"q": "zzzz"}).status_code == 404
    assert entorno.http.get("/devoluciones/buscar", params={"q": "99999"}).status_code == 404
    assert entorno.http.get("/devoluciones/buscar", params={"q": " "}).status_code == 400
    entorno.como("cajero_b")
    assert entorno.http.get("/devoluciones/buscar", params={"q": str(venta_id)}).status_code == 404  # otra sucursal
    entorno.como("admin_ajeno")
    assert entorno.http.get("/devoluciones/buscar", params={"q": str(venta_id)}).status_code == 404  # otra empresa


# ---------------------------------------------------------------------------------------------------------------
# Sincronización móvil: mismas reglas, plazo medido con la fecha del dispositivo
# ---------------------------------------------------------------------------------------------------------------

def _venta_movil(entorno, fecha: datetime, uuid="v-movil"):
    entorno.como("cajero")
    r = entorno.http.post("/sync/operaciones", json={"operaciones": [{
        "uuid": uuid, "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["suc_a"], "fecha": fecha.isoformat(),
        "items": [entorno.item(cantidad=2)],
    }]})
    assert r.json()["resultados"][0]["status"] == "ok", r.text


def _devolucion_movil(entorno, fecha: datetime, uuid="d-movil", cantidad=1):
    return entorno.http.post("/sync/operaciones", json={"devoluciones": [{
        "uuid": uuid, "venta_uuid": "v-movil", "tipo": "devolucion", "sucursal_id": entorno.ids["suc_a"], "fecha": fecha.isoformat(),
        "items_devueltos": [entorno.item(cantidad=cantidad)],
    }]}).json()["resultados"][0]


def test_sync_rechaza_una_devolucion_hecha_pasado_el_plazo(entorno):
    ahora = datetime.now(timezone.utc)
    _venta_movil(entorno, ahora - timedelta(days=10))

    r = _devolucion_movil(entorno, ahora)  # la venta tiene 10 días

    assert r["status"] == "conflict" and r["message"] == MENSAJE_PLAZO
    assert entorno.stock("camisa_M") == STOCK - 2


def test_sync_acepta_una_devolucion_hecha_sin_red_dentro_del_plazo_aunque_llegue_tarde(entorno):
    ahora = datetime.now(timezone.utc)
    _venta_movil(entorno, ahora - timedelta(days=10))

    # el cajero la hizo sin red 2 días después de la venta y recién sincroniza hoy
    r = _devolucion_movil(entorno, ahora - timedelta(days=8))

    assert r["status"] == "ok", r
    assert entorno.stock("camisa_M") == STOCK - 1


def test_sync_sigue_validando_las_cantidades(entorno):
    ahora = datetime.now(timezone.utc)
    _venta_movil(entorno, ahora - timedelta(days=1))

    r = _devolucion_movil(entorno, ahora, cantidad=3)

    assert r["status"] == "conflict" and "solo se pueden devolver 2" in r["message"]
