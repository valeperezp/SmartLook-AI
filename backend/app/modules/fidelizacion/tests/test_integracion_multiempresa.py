"""Integración del aislamiento por empresa (trabajo de la compañera) con el canje de puntos y los pagos (CU17).

Cubre lo que cada parte probaba por separado pero que juntas pueden romperse al fusionar:
- vender con canje respeta el aislamiento: no se canjean puntos vendiendo productos de otra empresa;
- una venta de otra empresa no se ve, aunque tenga canje;
- un pago QR rechazado se guarda como `fallido` (también en ventas presenciales) y, si la venta era online con canje, se cancela
  y los puntos vuelven al cliente.

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
from app.modules.fidelizacion import service as fidelizacion
from app.modules.inventario.models import Inventario
from app.modules.pagos import service as pagos_service
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import PuntosCliente
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta
from app.shared.db.session import Base, get_db

SALDO = 5


class Entorno:
    def __init__(self, client, Sesion, ids, actual):
        self.http, self.Sesion, self.ids, self._actual = client, Sesion, ids, actual

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def items(self, producto="camisa"):
        return [{"producto_id": self.ids[producto], "talla_id": self.ids[f"talla_{producto}"], "color_id": self.ids[f"color_{producto}"], "cantidad": 2}]

    def saldo(self) -> int:
        with self.Sesion() as db:
            return fidelizacion.saldo_de(db, self.ids["cliente"])

    def estado_de(self, modelo, id_):
        with self.Sesion() as db:
            return db.get(modelo, id_).estado

    def pago_qr_con_comprobante(self, venta_id: int) -> int:
        """Crea el pago QR de la venta y le pone un comprobante (lo que hace la app antes de que el cajero decida)."""
        with self.Sesion() as db:
            pago = pagos_service.crear_pago_qr(db, venta_id)
            pago.comprobante_path = "comprobantes/prueba.png"
            db.commit()
            return pago.id

    def rechazar(self, pago_id: int, quien="cajero"):
        with self.Sesion() as db:
            return pagos_service.confirmar_pago_qr(db, pago_id, aprobar=False, usuario_id=self.ids[quien], motivo="no coincide")


@pytest.fixture()
def entorno():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = Sesion()
    a, b = Empresa(nombre="Tienda A", slug="a"), Empresa(nombre="Tienda B", slug="b")
    db.add_all([a, b])
    db.flush()
    suc_a, suc_b = Sucursal(empresa_id=a.id, nombre="Centro", direccion="x"), Sucursal(empresa_id=b.id, nombre="Ajena", direccion="y")
    cat_a, cat_b = Categoria(empresa_id=a.id, nombre="Ropa"), Categoria(empresa_id=b.id, nombre="Ropa B")
    talla_a, talla_b = Talla(empresa_id=a.id, nombre="M"), Talla(empresa_id=b.id, nombre="M")
    color_a, color_b = Color(empresa_id=a.id, nombre="Negro"), Color(empresa_id=b.id, nombre="Negro")
    db.add_all([suc_a, suc_b, cat_a, cat_b, talla_a, talla_b, color_a, color_b])
    db.flush()
    camisa = Producto(empresa_id=a.id, nombre="Camisa A", precio=100, categoria_id=cat_a.id)
    ajena = Producto(empresa_id=b.id, nombre="Camisa B", precio=100, categoria_id=cat_b.id)
    usuarios = {
        "cajero": Usuario(nombre="Cajero A", email="ca@a.bo", rol="cajero", empresa_id=a.id, sucursal_id=suc_a.id),
        "cliente": Usuario(nombre="Cliente A", email="cl@a.bo", rol="cliente", empresa_id=a.id),
        "admin_ajeno": Usuario(nombre="Admin B", email="ad@b.bo", rol="administrador", empresa_id=b.id),
    }
    db.add_all([camisa, ajena, *usuarios.values()])
    db.flush()
    db.add(Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=talla_a.id, color_id=color_a.id, cantidad_disponible=50))
    db.add(Inventario(producto_id=ajena.id, sucursal_id=suc_b.id, talla_id=talla_b.id, color_id=color_b.id, cantidad_disponible=50))
    db.add(PuntosCliente(empresa_id=a.id, cliente_id=usuarios["cliente"].id, saldo=SALDO))
    db.commit()
    ids = {
        "suc_a": suc_a.id, "camisa": camisa.id, "ajena": ajena.id, "talla_camisa": talla_a.id, "color_camisa": color_a.id,
        "talla_ajena": talla_b.id, "color_ajena": color_b.id, **{k: u.id for k, u in usuarios.items()},
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


def _vender_con_canje(entorno, puntos=3, producto="camisa"):
    entorno.como("cajero")
    return entorno.http.post("/ventas", json={"sucursal_id": entorno.ids["suc_a"], "cliente_id": entorno.ids["cliente"],
                                              "items": entorno.items(producto), "puntos_a_canjear": puntos})


def test_vender_con_canje_funciona_con_el_aislamiento_por_empresa(entorno):
    """El router ahora pasa `empresa_id`: el canje sigue funcionando y descuenta como antes."""
    r = _vender_con_canje(entorno, puntos=3)

    assert r.status_code == 201, r.text
    assert r.json()["total"] == 200 - 30
    assert entorno.saldo() == SALDO - 3


def test_no_se_canjean_puntos_vendiendo_productos_de_otra_empresa(entorno):
    r = _vender_con_canje(entorno, puntos=3, producto="ajena")

    assert r.status_code == 404  # el aislamiento rechaza el producto ajeno ANTES de tocar los puntos
    assert entorno.saldo() == SALDO
    with entorno.Sesion() as db:
        assert db.query(Venta).count() == 0


def test_una_venta_con_canje_no_se_ve_desde_otra_empresa(entorno):
    venta_id = _vender_con_canje(entorno).json()["id"]

    entorno.como("admin_ajeno")
    assert entorno.http.get(f"/ventas/{venta_id}").status_code == 404
    entorno.como("cajero")
    assert entorno.http.get(f"/ventas/{venta_id}").status_code == 200


def test_un_pago_qr_rechazado_en_una_venta_presencial_se_guarda_como_fallido(entorno):
    """Regresión: el commit del rechazo quedó una vez dentro del `if` de ventas online y no guardaba el estado en las presenciales."""
    venta_id = _vender_con_canje(entorno, puntos=0).json()["id"]
    pago_id = entorno.pago_qr_con_comprobante(venta_id)

    entorno.rechazar(pago_id)

    from app.modules.pagos.models import Pago

    assert entorno.estado_de(Pago, pago_id) == "fallido"


def test_un_pago_qr_rechazado_en_una_venta_online_con_canje_la_cancela_y_devuelve_los_puntos(entorno):
    entorno.como("cliente")
    venta = entorno.http.post("/ventas/online", json={"sucursal_id": entorno.ids["suc_a"], "items": entorno.items(), "puntos_a_canjear": 3})
    assert venta.status_code == 201, venta.text
    assert entorno.saldo() == SALDO - 3
    pago_id = entorno.pago_qr_con_comprobante(venta.json()["id"])

    entorno.rechazar(pago_id)

    from app.modules.pagos.models import Pago

    assert entorno.estado_de(Pago, pago_id) == "fallido"
    assert entorno.estado_de(Venta, venta.json()["id"]) == "cancelada"
    assert entorno.saldo() == SALDO  # los 3 puntos canjeados volvieron


def test_la_sincronizacion_pasa_la_empresa_del_usuario_a_ventas_y_reservas(entorno):
    """El `empresa_id` sale del usuario autenticado (JWT): una venta offline de una sucursal ajena se rechaza."""
    entorno.como("cajero")
    r = entorno.http.post("/sync/operaciones", json={"operaciones": [{
        "uuid": "v-ajena", "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["suc_a"],
        "items": [{"producto_id": entorno.ids["ajena"], "talla_id": entorno.ids["talla_ajena"], "color_id": entorno.ids["color_ajena"], "cantidad": 1}],
    }]})

    assert r.json()["resultados"][0]["status"] == "conflict"
    with entorno.Sesion() as db:
        assert db.query(Venta).count() == 0
