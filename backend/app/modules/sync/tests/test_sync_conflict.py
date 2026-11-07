"""CU13 — Resolución de conflictos de sincronización (lado servidor).

Un dispositivo vendió offline más de lo que hay en el servidor. Al sincronizar, el backend debe:
- responder `status: "conflict"` para esa venta (con el motivo),
- NO guardar la venta ni sus ítems,
- NO tocar el stock del servidor,
- recordar el conflicto (idempotencia: reenviar el mismo uuid devuelve el mismo conflicto).

La prueba usa SQLite en memoria (no toca ninguna base real) y el endpoint real `POST /sync/operaciones`.
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

STOCK_SERVIDOR = 3


@pytest.fixture()
def entorno():
    """BD en memoria con una empresa, una sucursal, un cajero y UNA prenda con STOCK_SERVIDOR unidades."""
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = Sesion()
    empresa = Empresa(nombre="SmartLook Test", slug="smartlook-test")
    db.add(empresa)
    db.flush()
    sucursal = Sucursal(empresa_id=empresa.id, nombre="Centro", direccion="Av. Test 1")
    categoria = Categoria(empresa_id=empresa.id, nombre="Camisas")
    talla = Talla(empresa_id=empresa.id, nombre="M")
    color = Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([sucursal, categoria, talla, color])
    db.flush()
    cajero = Usuario(nombre="Cajero Test", email="cajero@test.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=sucursal.id)
    producto = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=categoria.id)
    db.add_all([cajero, producto])
    db.flush()
    inventario = Inventario(producto_id=producto.id, sucursal_id=sucursal.id, talla_id=talla.id, color_id=color.id,
                            cantidad_disponible=STOCK_SERVIDOR)
    db.add(inventario)
    db.commit()
    ids = {"sucursal": sucursal.id, "producto": producto.id, "talla": talla.id, "color": color.id,
           "inventario": inventario.id, "cajero": cajero.id}
    db.close()

    def _db():
        sesion = Sesion()
        try:
            yield sesion
        finally:
            sesion.close()

    def _usuario():
        sesion = Sesion()
        try:
            return sesion.get(Usuario, ids["cajero"])  # objeto desligado: solo se leen sus columnas
        finally:
            sesion.close()

    app.dependency_overrides[get_db] = _db
    app.dependency_overrides[get_current_user] = _usuario
    try:
        yield TestClient(app), Sesion, ids
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


def _venta(ids, uuid, cantidad):
    return {
        "uuid": uuid,
        "tipo_operacion": "VENTA_CONTADO",
        "sucursal_id": ids["sucursal"],
        "cajero_id": ids["cajero"],
        "total_centavos": 10000 * cantidad,
        "items": [{"producto_id": ids["producto"], "talla_id": ids["talla"], "color_id": ids["color"],
                   "cantidad": cantidad, "precio_unitario_centavos": 10000}],
    }


def _stock(Sesion, ids):
    with Sesion() as db:
        return db.get(Inventario, ids["inventario"]).cantidad_disponible


def _contar(Sesion, modelo):
    with Sesion() as db:
        return db.query(modelo).count()


def test_venta_que_excede_el_stock_responde_conflict_y_no_se_guarda(entorno):
    cliente, Sesion, ids = entorno

    r = cliente.post("/sync/operaciones", json={"operaciones": [_venta(ids, "venta-sin-stock", STOCK_SERVIDOR + 2)]})

    assert r.status_code == 200
    [resultado] = r.json()["resultados"]
    assert resultado["uuid"] == "venta-sin-stock"
    assert resultado["status"] == "conflict"
    assert "Stock insuficiente" in resultado["message"]
    assert resultado.get("id_servidor") is None
    # La venta NO se guardó: ni cabecera, ni ítems, ni movimientos de inventario
    assert _contar(Sesion, Venta) == 0
    assert _contar(Sesion, VentaItem) == 0
    assert _contar(Sesion, MovimientoInventario) == 0
    # El stock del servidor quedó intacto
    assert _stock(Sesion, ids) == STOCK_SERVIDOR


def test_el_conflicto_queda_registrado_y_reenviar_el_uuid_devuelve_el_mismo_conflicto(entorno):
    cliente, Sesion, ids = entorno
    lote = {"operaciones": [_venta(ids, "venta-repetida", STOCK_SERVIDOR + 1)]}

    primero = cliente.post("/sync/operaciones", json=lote).json()["resultados"][0]
    # Aunque ahora hubiera stock de sobra, el uuid ya tiene su resultado: no se reabre (idempotencia)
    with Sesion() as db:
        db.get(Inventario, ids["inventario"]).cantidad_disponible = 50
        db.commit()
    segundo = cliente.post("/sync/operaciones", json=lote).json()["resultados"][0]

    assert primero["status"] == segundo["status"] == "conflict"
    assert primero["message"] == segundo["message"]
    assert _contar(Sesion, Venta) == 0
    with Sesion() as db:
        registros = db.query(SyncOperacion).filter_by(uuid="venta-repetida").all()
        assert [(x.estado) for x in registros] == ["conflict"]  # un solo registro, no se duplica


def test_lote_mixto_el_conflicto_no_arrastra_a_la_venta_valida(entorno):
    cliente, Sesion, ids = entorno
    lote = {"operaciones": [_venta(ids, "venta-ok", 1), _venta(ids, "venta-excede", STOCK_SERVIDOR)]}

    r = cliente.post("/sync/operaciones", json=lote)

    estados = {x["uuid"]: x["status"] for x in r.json()["resultados"]}
    assert estados == {"venta-ok": "ok", "venta-excede": "conflict"}  # quedan 2 y se piden 3
    assert _contar(Sesion, Venta) == 1  # solo la válida
    assert _stock(Sesion, ids) == STOCK_SERVIDOR - 1  # solo se descontó la venta válida


def test_venta_con_stock_suficiente_si_se_guarda(entorno):
    """Control: confirma que la prueba de conflicto falla por el stock y no por un fallo del entorno de prueba."""
    cliente, Sesion, ids = entorno

    r = cliente.post("/sync/operaciones", json={"operaciones": [_venta(ids, "venta-valida", STOCK_SERVIDOR)]})

    [resultado] = r.json()["resultados"]
    assert resultado["status"] == "ok"
    assert isinstance(resultado["id_servidor"], int)
    assert _contar(Sesion, Venta) == 1
    assert _stock(Sesion, ids) == 0
