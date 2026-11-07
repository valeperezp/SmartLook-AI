"""CU13 — Conflictos de sincronización por falta de stock y su resolución manual (lado servidor).

Un dispositivo vendió offline más de lo que hay en el servidor. Al sincronizar, el backend debe:
- guardar la venta con estado `en_conflicto` y sus ítems (respuesta `status: "en_conflicto"` con el motivo),
- NO descontar stock ni registrar movimientos de inventario,
- recordar el resultado (idempotencia: reenviar el mismo uuid devuelve la misma venta),
y un encargado (de esa sucursal) o un administrador la resuelve: ANULAR, AJUSTAR (otra variante) o FORZAR.

Usa SQLite en memoria (no toca ninguna base real) y los endpoints reales.
Ejecutar desde `backend/`:  python -m pytest app/modules/sync/tests -v
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app  # importa todos los routers y, con ellos, todos los modelos
from app.modules.auth.service import get_current_user
from app.modules.catalogo.models import Categoria, Color, Producto, Talla
from app.modules.empresas.models import Empresa
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import SyncOperacion
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.db.session import Base, get_db

STOCK_M = 3  # lo que hay en el servidor de la talla M
STOCK_L = 10  # y de la talla L


class Entorno:
    """BD en memoria + cliente HTTP + quién es el usuario que hace cada petición."""

    def __init__(self, client, Sesion, ids, actual):
        self.http, self.Sesion, self.ids, self._actual = client, Sesion, ids, actual

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def stock(self, talla: str = "M", sucursal: str = "sucursal_a") -> int:
        with self.Sesion() as db:
            return db.get(Inventario, self.ids[f"inv_{talla}_{sucursal}"]).cantidad_disponible

    def contar(self, modelo) -> int:
        with self.Sesion() as db:
            return db.query(modelo).count()

    def venta(self, venta_id: int) -> Venta:
        with self.Sesion() as db:
            v = db.get(Venta, venta_id)
            _ = v.items  # carga los ítems antes de cerrar la sesión
            db.expunge_all()
            return v

    def enviar_venta(self, uuid: str, cantidad: int, talla: str = "M"):
        self.como("cajero")
        r = self.http.post("/sync/operaciones", json={"operaciones": [{
            "uuid": uuid, "tipo_operacion": "VENTA_CONTADO", "sucursal_id": self.ids["sucursal_a"],
            "cajero_id": self.ids["cajero"], "total_centavos": 10000 * cantidad,
            "items": [{"producto_id": self.ids["producto"], "talla_id": self.ids[f"talla_{talla}"], "color_id": self.ids["color"],
                       "cantidad": cantidad, "precio_unitario_centavos": 10000}],
        }]})
        assert r.status_code == 200, r.text
        return r.json()["resultados"][0]


@pytest.fixture()
def entorno():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = Sesion()
    empresa = Empresa(nombre="SmartLook Test", slug="smartlook-test")
    db.add(empresa)
    db.flush()
    suc_a = Sucursal(empresa_id=empresa.id, nombre="Centro", direccion="Av. Test 1")
    suc_b = Sucursal(empresa_id=empresa.id, nombre="Norte", direccion="Av. Test 2")
    categoria = Categoria(empresa_id=empresa.id, nombre="Camisas")
    talla_m, talla_l = Talla(empresa_id=empresa.id, nombre="M"), Talla(empresa_id=empresa.id, nombre="L")
    color = Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([suc_a, suc_b, categoria, talla_m, talla_l, color])
    db.flush()
    usuarios = {
        "cajero": Usuario(nombre="Cajero Centro", email="cajero@test.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "encargado_a": Usuario(nombre="Encargado Centro", email="enc.a@test.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "encargado_b": Usuario(nombre="Encargado Norte", email="enc.b@test.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_b.id),
        "admin": Usuario(nombre="Admin", email="admin@test.bo", rol="administrador", empresa_id=empresa.id),
    }
    producto = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=categoria.id)
    db.add_all([*usuarios.values(), producto])
    db.flush()
    inv_m = Inventario(producto_id=producto.id, sucursal_id=suc_a.id, talla_id=talla_m.id, color_id=color.id, cantidad_disponible=STOCK_M)
    inv_l = Inventario(producto_id=producto.id, sucursal_id=suc_a.id, talla_id=talla_l.id, color_id=color.id, cantidad_disponible=STOCK_L)
    db.add_all([inv_m, inv_l])
    db.commit()
    ids = {
        "sucursal_a": suc_a.id, "sucursal_b": suc_b.id, "producto": producto.id, "talla_M": talla_m.id, "talla_L": talla_l.id,
        "color": color.id, "inv_M_sucursal_a": inv_m.id, "inv_L_sucursal_a": inv_l.id,
        **{nombre: u.id for nombre, u in usuarios.items()},
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
        sesion = Sesion()
        try:
            return sesion.get(Usuario, actual["id"])  # objeto desligado: solo se leen sus columnas
        finally:
            sesion.close()

    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_current_user] = _usuario
    try:
        yield Entorno(TestClient(app), Sesion, ids, actual)
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


# ---------------------------------------------------------------------------------------------------------------
# Sincronización: una venta sin stock queda EN_CONFLICTO (no se rechaza, no se pierde)
# ---------------------------------------------------------------------------------------------------------------

def test_venta_que_excede_el_stock_queda_en_conflicto_con_sus_items_y_sin_descontar_stock(entorno):
    resultado = entorno.enviar_venta("venta-sin-stock", STOCK_M + 2)

    assert resultado["uuid"] == "venta-sin-stock"
    assert resultado["status"] == "en_conflicto"
    assert resultado["entidad"] == "venta"
    assert isinstance(resultado["id_servidor"], int)
    assert "Stock insuficiente en Camisa Oxford Talla M" in resultado["message"]
    # La venta SÍ se guardó, con sus ítems y como EN_CONFLICTO...
    venta = entorno.venta(resultado["id_servidor"])
    assert venta.estado == "en_conflicto"
    assert [(i.cantidad, i.talla_id) for i in venta.items] == [(STOCK_M + 2, entorno.ids["talla_M"])]
    assert float(venta.total) == 100 * (STOCK_M + 2)
    # ...pero el inventario real no se tocó
    assert entorno.stock("M") == STOCK_M
    assert entorno.contar(MovimientoInventario) == 0


def test_reenviar_el_mismo_uuid_devuelve_la_misma_venta_en_conflicto_sin_duplicar(entorno):
    primero = entorno.enviar_venta("venta-repetida", STOCK_M + 1)
    segundo = entorno.enviar_venta("venta-repetida", STOCK_M + 1)

    assert primero["status"] == segundo["status"] == "en_conflicto"
    assert primero["id_servidor"] == segundo["id_servidor"]
    assert entorno.contar(Venta) == 1
    assert entorno.contar(VentaItem) == 1
    with entorno.Sesion() as db:
        assert db.query(SyncOperacion).filter_by(uuid="venta-repetida").count() == 1


def test_lote_mixto_el_conflicto_no_arrastra_a_la_venta_valida(entorno):
    entorno.como("cajero")
    venta = lambda uuid, cantidad: {
        "uuid": uuid, "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["sucursal_a"],
        "items": [{"producto_id": entorno.ids["producto"], "talla_id": entorno.ids["talla_M"], "color_id": entorno.ids["color"], "cantidad": cantidad}],
    }
    r = entorno.http.post("/sync/operaciones", json={"operaciones": [venta("venta-ok", 1), venta("venta-excede", STOCK_M)]})

    estados = {x["uuid"]: x["status"] for x in r.json()["resultados"]}
    assert estados == {"venta-ok": "ok", "venta-excede": "en_conflicto"}  # quedan 2 y se piden 3
    assert entorno.stock("M") == STOCK_M - 1  # solo se descontó la venta válida
    with entorno.Sesion() as db:
        assert sorted(v.estado for v in db.query(Venta)) == ["completada", "en_conflicto"]


def test_venta_con_stock_suficiente_sigue_el_flujo_normal(entorno):
    """Control: el flujo normal no cambió (se guarda completada y descuenta stock)."""
    resultado = entorno.enviar_venta("venta-valida", STOCK_M)

    assert resultado["status"] == "ok"
    assert entorno.venta(resultado["id_servidor"]).estado == "completada"
    assert entorno.stock("M") == 0


def test_los_demas_conflictos_siguen_siendo_definitivos(entorno):
    """Solo la falta de stock es EN_CONFLICTO: un producto que no existe sigue rechazándose (`conflict`)."""
    entorno.como("cajero")
    r = entorno.http.post("/sync/operaciones", json={"operaciones": [{
        "uuid": "producto-ajeno", "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["sucursal_a"],
        "items": [{"producto_id": 99999, "cantidad": 1}],
    }]})

    assert r.json()["resultados"][0]["status"] == "conflict"
    assert entorno.contar(Venta) == 0


# ---------------------------------------------------------------------------------------------------------------
# Listado: GET /sync/conflictos
# ---------------------------------------------------------------------------------------------------------------

def test_el_encargado_de_la_sucursal_ve_el_conflicto_con_motivo_e_items(entorno):
    resultado = entorno.enviar_venta("v1", STOCK_M + 1)
    entorno.como("encargado_a")

    r = entorno.http.get("/sync/conflictos")

    assert r.status_code == 200
    [c] = r.json()
    assert c["venta_id"] == resultado["id_servidor"]
    assert c["uuid"] == "v1"
    assert c["nombre_sucursal"] == "Centro" and c["nombre_cajero"] == "Cajero Centro"
    assert "Stock insuficiente en Camisa Oxford Talla M" in c["motivo"]
    assert c["items"][0] == {
        "producto_id": entorno.ids["producto"], "nombre_producto": "Camisa Oxford", "talla_id": entorno.ids["talla_M"],
        "nombre_talla": "M", "color_id": entorno.ids["color"], "nombre_color": "Negro", "cantidad": STOCK_M + 1, "precio_unitario": 100.0,
    }


def test_el_listado_se_filtra_por_sucursal_y_por_rol(entorno):
    entorno.enviar_venta("v1", STOCK_M + 1)

    entorno.como("encargado_b")  # encargado de OTRA sucursal
    assert entorno.http.get("/sync/conflictos").json() == []
    entorno.como("admin")
    assert len(entorno.http.get("/sync/conflictos").json()) == 1  # el administrador ve todas
    assert entorno.http.get(f"/sync/conflictos?sucursal_id={entorno.ids['sucursal_b']}").json() == []
    entorno.como("cajero")
    assert entorno.http.get("/sync/conflictos").status_code == 403  # solo encargados y administradores


# ---------------------------------------------------------------------------------------------------------------
# Resolución: POST /sync/conflictos/{venta_id}/resolver
# ---------------------------------------------------------------------------------------------------------------

def _resolver(entorno, venta_id, accion, items=None, quien="encargado_a"):
    entorno.como(quien)
    cuerpo = {"accion": accion}
    if items is not None:
        cuerpo["items"] = items
    return entorno.http.post(f"/sync/conflictos/{venta_id}/resolver", json=cuerpo)


def test_anular_deja_la_venta_anulada_sin_tocar_el_stock(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 1)["id_servidor"]

    r = _resolver(entorno, venta_id, "ANULAR")

    assert r.status_code == 200
    assert r.json() == {"venta_id": venta_id, "accion": "ANULAR", "estado": "anulada", "total": 100.0 * (STOCK_M + 1)}
    assert entorno.venta(venta_id).estado == "anulada"
    assert entorno.stock("M") == STOCK_M and entorno.contar(MovimientoInventario) == 0
    assert entorno.http.get("/sync/conflictos").json() == []  # ya no está en la lista
    # el dispositivo que la reenvíe recibe el resultado final: rechazada
    assert entorno.enviar_venta("v1", STOCK_M + 1)["status"] == "conflict"


def test_forzar_descuenta_el_stock_aunque_quede_negativo(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 2)["id_servidor"]

    r = _resolver(entorno, venta_id, "FORZAR")

    assert r.status_code == 200 and r.json()["estado"] == "completada"
    assert entorno.venta(venta_id).estado == "completada"
    assert entorno.stock("M") == STOCK_M - (STOCK_M + 2)  # -2: el encargado asume la pérdida
    assert entorno.contar(MovimientoInventario) == 1
    # reenviar el uuid ahora responde ok con el mismo id
    reenvio = entorno.enviar_venta("v1", STOCK_M + 2)
    assert (reenvio["status"], reenvio["id_servidor"]) == ("ok", venta_id)


def test_ajustar_cambia_la_variante_verifica_stock_y_descuenta(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 1)["id_servidor"]
    otra_talla = [{"producto_id": entorno.ids["producto"], "talla_id": entorno.ids["talla_L"], "color_id": entorno.ids["color"], "cantidad": 2}]

    r = _resolver(entorno, venta_id, "AJUSTAR", items=otra_talla)

    assert r.status_code == 200 and r.json()["estado"] == "completada"
    assert r.json()["total"] == 200.0  # recalculado con las prendas nuevas
    venta = entorno.venta(venta_id)
    assert venta.estado == "completada"
    assert [(i.talla_id, i.cantidad) for i in venta.items] == [(entorno.ids["talla_L"], 2)]
    assert entorno.stock("L") == STOCK_L - 2
    assert entorno.stock("M") == STOCK_M  # la talla original no se tocó


def test_ajustar_sin_stock_suficiente_falla_y_la_venta_sigue_en_conflicto(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 1)["id_servidor"]
    demasiadas = [{"producto_id": entorno.ids["producto"], "talla_id": entorno.ids["talla_L"], "color_id": entorno.ids["color"], "cantidad": STOCK_L + 1}]

    r = _resolver(entorno, venta_id, "AJUSTAR", items=demasiadas)

    assert r.status_code == 400 and "Stock insuficiente" in r.json()["detail"]
    assert entorno.venta(venta_id).estado == "en_conflicto"
    assert entorno.stock("L") == STOCK_L
    assert _resolver(entorno, venta_id, "AJUSTAR", items=[]).status_code == 400  # sin prendas tampoco


def test_una_venta_resuelta_no_se_puede_resolver_dos_veces(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 1)["id_servidor"]
    assert _resolver(entorno, venta_id, "FORZAR").status_code == 200

    r = _resolver(entorno, venta_id, "FORZAR")

    assert r.status_code == 409
    assert entorno.stock("M") == STOCK_M - (STOCK_M + 1)  # no se descontó dos veces


def test_un_encargado_de_otra_sucursal_no_puede_resolver_ni_ve_la_venta(entorno):
    venta_id = entorno.enviar_venta("v1", STOCK_M + 1)["id_servidor"]

    assert _resolver(entorno, venta_id, "ANULAR", quien="encargado_b").status_code == 404
    assert _resolver(entorno, venta_id, "ANULAR", quien="cajero").status_code == 403
    assert entorno.venta(venta_id).estado == "en_conflicto"
    # el administrador sí puede
    assert _resolver(entorno, venta_id, "ANULAR", quien="admin").status_code == 200


def test_una_venta_normal_no_se_puede_resolver(entorno):
    venta_id = entorno.enviar_venta("v-ok", 1)["id_servidor"]

    assert _resolver(entorno, venta_id, "ANULAR").status_code == 409
    assert entorno.venta(venta_id).estado == "completada"


def test_una_devolucion_sobre_una_venta_en_conflicto_espera_a_que_se_resuelva(entorno):
    entorno.enviar_venta("v1", STOCK_M + 1)
    entorno.como("cajero")

    r = entorno.http.post("/sync/operaciones", json={"devoluciones": [{
        "uuid": "dev-1", "venta_uuid": "v1", "tipo": "devolucion", "sucursal_id": entorno.ids["sucursal_a"],
        "items_devueltos": [{"producto_id": entorno.ids["producto"], "talla_id": entorno.ids["talla_M"], "color_id": entorno.ids["color"], "cantidad": 1}],
    }]})

    [res] = r.json()["resultados"]
    assert res["status"] == "pendiente" and "conflicto" in res["message"]
    assert entorno.contar(MovimientoInventario) == 0
