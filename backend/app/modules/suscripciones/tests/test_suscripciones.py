"""CU16 — "Avísame cuando llegue": el servidor guarda las suscripciones y las marca `notificado` cuando entra stock.

- `POST /suscripciones` crea una suscripción `pendiente` (idempotente, multi-empresa).
- Cuando se SUMA stock de esa variante (entrada de inventario, ajuste hacia arriba, carga inicial, devolución...) las
  suscripciones que coinciden pasan a `notificado`; las que no coinciden se quedan como están.
- `GET /suscripciones/mis-notificaciones` muestra al cliente sus avisos.

Usa SQLite en memoria (no toca ninguna base real). Ejecutar desde `backend/`:  python -m pytest app/modules -v
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.modules.auth.service import get_current_user
from app.modules.catalogo.models import Categoria, Color, Producto, Talla
from app.modules.empresas.models import Empresa
from app.modules.inventario.models import Inventario
from app.modules.suscripciones.models import SuscripcionStock
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.db.session import Base, get_db


class Entorno:
    def __init__(self, client, Sesion, ids, actual):
        self.http, self.Sesion, self.ids, self._actual = client, Sesion, ids, actual

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def pedir(self, quien="cliente", producto="camisa", talla="M", color=True, sucursal="suc_a", **extra):
        self.como(quien)
        cuerpo = {"producto_id": self.ids[producto], "talla_id": self.ids[f"talla_{talla}"] if talla else None,
                  "color_id": self.ids["color"] if color else None, "sucursal_id": self.ids[sucursal] if sucursal else None, **extra}
        return self.http.post("/suscripciones", json=cuerpo)

    def entrada(self, inv: str, cantidad: int = 5, quien="admin"):
        self.como(quien)
        return self.http.post("/inventario/movimientos", json={"inventario_id": self.ids[f"inv_{inv}"], "tipo": "entrada", "cantidad": cantidad})

    def estado(self, suscripcion_id: int) -> str:
        with self.Sesion() as db:
            return db.get(SuscripcionStock, suscripcion_id).estado

    def notificaciones(self, quien="cliente", **params):
        self.como(quien)
        return self.http.get("/suscripciones/mis-notificaciones", params=params).json()


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
    cat_otra = Categoria(empresa_id=otra.id, nombre="Ropa ajena")
    t_m, t_l = Talla(empresa_id=empresa.id, nombre="M"), Talla(empresa_id=empresa.id, nombre="L")
    color = Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([suc_a, suc_b, suc_otra, cat, cat_otra, t_m, t_l, color])
    db.flush()
    camisa = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=cat.id)
    polo = Producto(empresa_id=empresa.id, nombre="Polo", precio=50, categoria_id=cat.id)
    ajeno = Producto(empresa_id=otra.id, nombre="Producto Ajeno", precio=10, categoria_id=cat_otra.id)
    usuarios = {
        "cliente": Usuario(nombre="Cliente 1", email="c1@t.bo", rol="cliente", empresa_id=empresa.id),
        "cliente2": Usuario(nombre="Cliente 2", email="c2@t.bo", rol="cliente", empresa_id=empresa.id),
        "cliente_ajeno": Usuario(nombre="Cliente Ajeno", email="c3@o.bo", rol="cliente", empresa_id=otra.id),
        "admin": Usuario(nombre="Admin", email="ad@t.bo", rol="administrador", empresa_id=empresa.id),
        "encargado": Usuario(nombre="Encargado A", email="e@t.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "cajero": Usuario(nombre="Cajero A", email="ca@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_a.id),
    }
    db.add_all([camisa, polo, ajeno, *usuarios.values()])
    db.flush()
    # Todo agotado (stock 0): es lo que se espera cuando alguien pide "avísame"
    inv = {
        "camisa_A_M": Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=t_m.id, color_id=color.id, cantidad_disponible=0),
        "camisa_A_L": Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=t_l.id, color_id=color.id, cantidad_disponible=0),
        "camisa_B_M": Inventario(producto_id=camisa.id, sucursal_id=suc_b.id, talla_id=t_m.id, color_id=color.id, cantidad_disponible=0),
        "polo_A_M": Inventario(producto_id=polo.id, sucursal_id=suc_a.id, talla_id=t_m.id, color_id=color.id, cantidad_disponible=0),
    }
    db.add_all(inv.values())
    db.commit()
    ids = {
        "suc_a": suc_a.id, "suc_b": suc_b.id, "suc_otra": suc_otra.id, "camisa": camisa.id, "polo": polo.id, "ajeno": ajeno.id,
        "talla_M": t_m.id, "talla_L": t_l.id, "color": color.id,
        **{f"inv_{k}": v.id for k, v in inv.items()}, **{k: u.id for k, u in usuarios.items()},
    }
    db.close()

    actual = {"id": ids["cliente"]}

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
# POST /suscripciones
# ---------------------------------------------------------------------------------------------------------------

def test_el_cliente_se_suscribe_y_queda_pendiente(entorno):
    r = entorno.pedir()

    assert r.status_code == 201, r.text
    s = r.json()
    assert (s["estado"], s["visto"], s["notificado_en"]) == ("pendiente", False, None)
    assert (s["nombre_producto"], s["nombre_talla"], s["nombre_color"], s["nombre_sucursal"]) == ("Camisa Oxford", "M", "Negro", "Centro")
    assert s["descripcion"] == "Camisa Oxford · Talla M · Negro"
    assert s["fecha"]


def test_pedir_dos_veces_lo_mismo_no_duplica(entorno):
    a = entorno.pedir().json()
    b = entorno.pedir().json()

    assert a["id"] == b["id"]
    with entorno.Sesion() as db:
        assert db.query(SuscripcionStock).count() == 1


def test_reenviar_el_mismo_uuid_no_duplica_aunque_cambie_lo_pedido(entorno):
    """Una suscripción hecha sin red se reenvía con el mismo uuid: el servidor la reconoce."""
    a = entorno.pedir(uuid="app-uuid-1").json()
    b = entorno.pedir(uuid="app-uuid-1", talla="L").json()

    assert a["id"] == b["id"]


def test_se_puede_pedir_cualquier_talla_color_o_sucursal(entorno):
    r = entorno.pedir(talla=None, color=False, sucursal=None)

    assert r.status_code == 201
    assert (r.json()["talla_id"], r.json()["color_id"], r.json()["sucursal_id"]) == (None, None, None)


def test_solo_los_clientes_se_suscriben(entorno):
    for quien in ("admin", "encargado", "cajero"):
        assert entorno.pedir(quien=quien).status_code == 403


def test_multitenant_no_se_puede_pedir_algo_de_otra_empresa(entorno):
    assert entorno.pedir(producto="ajeno").status_code == 404
    entorno.como("cliente")
    assert entorno.http.post("/suscripciones", json={"producto_id": entorno.ids["camisa"], "sucursal_id": entorno.ids["suc_otra"]}).status_code == 404
    entorno.como("cliente_ajeno")  # un cliente de otra empresa tampoco ve ni pide el producto de esta
    assert entorno.http.post("/suscripciones", json={"producto_id": entorno.ids["camisa"]}).status_code == 404


def test_si_ya_hay_stock_el_aviso_llega_de_una_vez(entorno):
    entorno.entrada("camisa_A_M", 3)

    s = entorno.pedir().json()  # p. ej. una suscripción hecha sin red que se envía cuando la prenda ya llegó

    assert s["estado"] == "notificado" and s["notificado_en"]


# ---------------------------------------------------------------------------------------------------------------
# El disparador: entra stock → notificado
# ---------------------------------------------------------------------------------------------------------------

def test_una_entrada_de_inventario_marca_la_suscripcion_como_notificada(entorno):
    sid = entorno.pedir().json()["id"]
    assert entorno.estado(sid) == "pendiente"

    r = entorno.entrada("camisa_A_M", 5)

    assert r.status_code == 201, r.text
    assert entorno.estado(sid) == "notificado"
    [aviso] = entorno.notificaciones()
    assert (aviso["id"], aviso["estado"], aviso["visto"]) == (sid, "notificado", False)
    assert aviso["notificado_en"]


def test_una_salida_de_inventario_no_notifica(entorno):
    sid = entorno.pedir().json()["id"]
    entorno.entrada("camisa_A_M", 5)
    nueva = entorno.pedir(talla="L").json()["id"]

    entorno.como("admin")
    entorno.http.post("/inventario/movimientos", json={"inventario_id": entorno.ids["inv_camisa_A_L"], "tipo": "salida", "cantidad": 1})

    assert entorno.estado(sid) == "notificado" and entorno.estado(nueva) == "pendiente"


def test_solo_se_notifican_las_suscripciones_que_coinciden(entorno):
    espera_M_A = entorno.pedir(talla="M", sucursal="suc_a").json()["id"]
    espera_L_A = entorno.pedir(talla="L", sucursal="suc_a").json()["id"]
    espera_M_B = entorno.pedir(talla="M", sucursal="suc_b").json()["id"]
    espera_polo = entorno.pedir(producto="polo").json()["id"]
    cualquier_talla = entorno.pedir(talla=None, sucursal="suc_a").json()["id"]
    cualquier_sucursal = entorno.pedir(talla="M", sucursal=None).json()["id"]

    entorno.entrada("camisa_A_M", 4)  # llegó la camisa M a la sucursal A

    assert entorno.estado(espera_M_A) == "notificado"
    assert entorno.estado(cualquier_talla) == "notificado"  # pedía cualquier talla en A
    assert entorno.estado(cualquier_sucursal) == "notificado"  # pedía la M en cualquier sucursal
    assert entorno.estado(espera_L_A) == "pendiente"  # otra talla
    assert entorno.estado(espera_M_B) == "pendiente"  # otra sucursal
    assert entorno.estado(espera_polo) == "pendiente"  # otro producto


def test_un_ajuste_hacia_arriba_notifica_y_hacia_abajo_no(entorno):
    sid = entorno.pedir().json()["id"]
    entorno.como("admin")
    arriba = entorno.http.post("/inventario/ajuste", json={"inventario_id": entorno.ids["inv_camisa_A_M"], "nueva_cantidad": 0})
    assert arriba.status_code == 200 and entorno.estado(sid) == "pendiente"  # 0 → 0: no entró nada

    r = entorno.http.post("/inventario/ajuste", json={"inventario_id": entorno.ids["inv_camisa_A_M"], "nueva_cantidad": 6})

    assert r.status_code == 200 and entorno.estado(sid) == "notificado"


def test_la_carga_inicial_de_una_variante_nueva_tambien_notifica(entorno):
    # una variante que la sucursal B nunca tuvo: se carga por primera vez
    sid = entorno.pedir(producto="polo", talla="M", sucursal="suc_b").json()["id"]
    entorno.como("admin")

    r = entorno.http.post("/inventario", json={"producto_id": entorno.ids["polo"], "sucursal_id": entorno.ids["suc_b"],
                                                "talla_id": entorno.ids["talla_M"], "color_id": entorno.ids["color"], "cantidad_inicial": 7})

    assert r.status_code == 201, r.text
    assert entorno.estado(sid) == "notificado"


def test_una_devolucion_que_repone_stock_notifica(entorno):
    """Lo devuelto vuelve a la estantería: también es una llegada."""
    entorno.entrada("camisa_A_M", 1)
    entorno.como("cajero")
    venta = entorno.http.post("/ventas", json={"sucursal_id": entorno.ids["suc_a"], "items": [
        {"producto_id": entorno.ids["camisa"], "talla_id": entorno.ids["talla_M"], "color_id": entorno.ids["color"], "cantidad": 1}]})
    assert venta.status_code == 201, venta.text  # se vendió la última camisa M: stock 0
    sid = entorno.pedir().json()["id"]
    assert entorno.estado(sid) == "pendiente"

    entorno.como("cajero")  # la devolución la registra el personal, no el cliente
    r = entorno.http.post("/devoluciones", json={"venta_id": venta.json()["id"], "tipo": "devolucion", "items_devueltos": [
        {"producto_id": entorno.ids["camisa"], "talla_id": entorno.ids["talla_M"], "color_id": entorno.ids["color"], "cantidad": 1}], "items_nuevos": []})

    assert r.status_code == 201, r.text
    assert entorno.estado(sid) == "notificado"


def test_una_suscripcion_ya_notificada_no_se_vuelve_a_notificar(entorno):
    sid = entorno.pedir().json()["id"]
    entorno.entrada("camisa_A_M", 2)
    with entorno.Sesion() as db:
        primera = db.get(SuscripcionStock, sid).notificado_en

    entorno.entrada("camisa_A_M", 2)

    with entorno.Sesion() as db:
        assert db.get(SuscripcionStock, sid).notificado_en == primera


# ---------------------------------------------------------------------------------------------------------------
# Mis notificaciones
# ---------------------------------------------------------------------------------------------------------------

def test_mis_notificaciones_solo_muestra_las_notificadas_y_las_mias(entorno):
    mia = entorno.pedir().json()["id"]
    entorno.pedir(talla="L")  # pendiente: no es una notificación
    entorno.pedir(quien="cliente2")  # de otro cliente
    entorno.entrada("camisa_A_M", 3)

    mias = entorno.notificaciones("cliente")
    de_otro = entorno.notificaciones("cliente2")

    assert [a["id"] for a in mias] == [mia]
    assert len(de_otro) == 1 and de_otro[0]["id"] != mia  # cliente2 pidió lo mismo y también recibe SU aviso
    assert entorno.notificaciones("cliente_ajeno") == []  # otra empresa: nada


def test_mias_lista_pendientes_y_notificadas(entorno):
    a = entorno.pedir().json()["id"]
    b = entorno.pedir(talla="L").json()["id"]
    entorno.entrada("camisa_A_M", 3)

    entorno.como("cliente")
    todas = {s["id"]: s["estado"] for s in entorno.http.get("/suscripciones/mias").json()}

    assert todas == {a: "notificado", b: "pendiente"}


def test_marcar_vistas_quita_los_avisos_de_las_nuevas(entorno):
    entorno.pedir()
    entorno.entrada("camisa_A_M", 3)
    assert len(entorno.notificaciones(solo_nuevas="true")) == 1

    entorno.como("cliente")
    r = entorno.http.post("/suscripciones/marcar-vistas")

    assert r.json() == {"marcadas": 1}
    assert entorno.notificaciones(solo_nuevas="true") == []
    assert len(entorno.notificaciones()) == 1  # el aviso sigue en su historial, ya visto
    assert entorno.notificaciones()[0]["visto"] is True
    assert entorno.http.post("/suscripciones/marcar-vistas").json() == {"marcadas": 0}


def test_las_rutas_de_cliente_no_las_usa_el_personal(entorno):
    entorno.como("admin")

    assert entorno.http.get("/suscripciones/mis-notificaciones").status_code == 403
    assert entorno.http.get("/suscripciones/mias").status_code == 403
    assert entorno.http.post("/suscripciones/marcar-vistas").status_code == 403
