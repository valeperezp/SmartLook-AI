"""CU17 — Puntos de fidelización: regla por empresa (backend), saldo y canje como descuento al vender.

Reglas que se prueban:
- la regla "cuánto vale un punto" viene del backend y es por empresa (por defecto 1000 centavos = 10 Bs),
- `GET /clientes/mis-puntos` devuelve el saldo del cliente logueado,
- al vender (online, presencial u offline con sync) `puntos_a_canjear` resta puntos y baja el total,
- está blindado: no se puede canjear más de lo que se tiene ni un descuento mayor al total,
- si una venta con canje se cancela, los puntos vuelven (una sola vez).

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
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import MovimientoPuntos, PuntosCliente
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta
from app.shared.db.session import Base, get_db

SALDO_INICIAL = 5  # puntos del cliente
PRECIO = 100  # por prenda → 2 prendas = 200; cada punto descuenta 10 (valor por defecto 1000 centavos)


class Entorno:
    def __init__(self, client, Sesion, ids, actual):
        self.http, self.Sesion, self.ids, self._actual = client, Sesion, ids, actual

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def saldo(self, quien: str = "cliente") -> int:
        with self.Sesion() as db:
            return fidelizacion.saldo_de(db, self.ids[quien])

    def venta(self, venta_id: int) -> Venta:
        with self.Sesion() as db:
            return db.get(Venta, venta_id)

    def contar(self, modelo) -> int:
        with self.Sesion() as db:
            return db.query(modelo).count()

    def items(self, cantidad: int = 2):
        return [{"producto_id": self.ids["producto"], "talla_id": self.ids["talla"], "color_id": self.ids["color"], "cantidad": cantidad}]

    def comprar_online(self, puntos: int, cantidad: int = 2):
        self.como("cliente")
        return self.http.post("/ventas/online", json={"sucursal_id": self.ids["sucursal"], "items": self.items(cantidad), "puntos_a_canjear": puntos})

    def vender_en_caja(self, puntos: int, cliente: str | None = "cliente", cantidad: int = 2):
        self.como("cajero")
        cuerpo = {"sucursal_id": self.ids["sucursal"], "items": self.items(cantidad), "puntos_a_canjear": puntos}
        if cliente:
            cuerpo["cliente_id"] = self.ids[cliente]
        return self.http.post("/ventas", json=cuerpo)


@pytest.fixture()
def entorno():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    Sesion = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    db = Sesion()
    empresa = Empresa(nombre="Tienda Test", slug="tienda-test")
    otra = Empresa(nombre="Otra Tienda", slug="otra-tienda")
    db.add_all([empresa, otra])
    db.flush()
    sucursal = Sucursal(empresa_id=empresa.id, nombre="Centro", direccion="Av. 1")
    categoria = Categoria(empresa_id=empresa.id, nombre="Camisas")
    talla, color = Talla(empresa_id=empresa.id, nombre="M"), Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([sucursal, categoria, talla, color])
    db.flush()
    cajero = Usuario(nombre="Cajero", email="cajero@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=sucursal.id)
    cliente = Usuario(nombre="Cliente", email="cliente@t.bo", rol="cliente", empresa_id=empresa.id)
    otro_cliente = Usuario(nombre="Otro", email="otro@t.bo", rol="cliente", empresa_id=empresa.id)
    cliente_ajeno = Usuario(nombre="Ajeno", email="ajeno@t.bo", rol="cliente", empresa_id=otra.id)
    admin = Usuario(nombre="Admin", email="admin@t.bo", rol="administrador", empresa_id=empresa.id)
    producto = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=PRECIO, categoria_id=categoria.id)
    db.add_all([cajero, cliente, otro_cliente, cliente_ajeno, admin, producto])
    db.flush()
    db.add(Inventario(producto_id=producto.id, sucursal_id=sucursal.id, talla_id=talla.id, color_id=color.id, cantidad_disponible=50))
    db.add(PuntosCliente(empresa_id=empresa.id, cliente_id=cliente.id, saldo=SALDO_INICIAL))
    db.commit()
    ids = {
        "empresa": empresa.id, "otra_empresa": otra.id, "sucursal": sucursal.id, "producto": producto.id, "talla": talla.id, "color": color.id,
        "cajero": cajero.id, "cliente": cliente.id, "otro_cliente": otro_cliente.id, "cliente_ajeno": cliente_ajeno.id, "admin": admin.id,
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
# Regla por empresa y saldo
# ---------------------------------------------------------------------------------------------------------------

def test_la_regla_viene_del_backend_por_defecto_1000_centavos(entorno):
    with entorno.Sesion() as db:
        assert fidelizacion.valor_punto_centavos(db, entorno.ids["empresa"]) == 1000
        assert fidelizacion.valor_punto_centavos(db, None) == 1000


def test_mis_puntos_devuelve_el_saldo_y_la_regla_de_la_empresa(entorno):
    entorno.como("cliente")

    r = entorno.http.get("/clientes/mis-puntos")

    assert r.status_code == 200
    assert r.json() == {"cliente_id": entorno.ids["cliente"], "saldo": SALDO_INICIAL, "valor_punto_centavos": 1000, "valor_saldo_centavos": 5000}


def test_un_cliente_sin_puntos_tiene_saldo_cero(entorno):
    entorno.como("otro_cliente")

    assert entorno.http.get("/clientes/mis-puntos").json()["saldo"] == 0


def test_mis_puntos_solo_para_clientes(entorno):
    entorno.como("cajero")

    assert entorno.http.get("/clientes/mis-puntos").status_code == 403


def test_el_administrador_cambia_la_regla_de_SU_empresa(entorno):
    entorno.como("admin")

    r = entorno.http.put("/clientes/regla-puntos", json={"valor_punto_centavos": 500})

    assert r.status_code == 200 and r.json() == {"valor_punto_centavos": 500}
    entorno.como("cliente")
    assert entorno.http.get("/clientes/mis-puntos").json()["valor_punto_centavos"] == 500
    with entorno.Sesion() as db:  # la otra empresa no cambió
        assert fidelizacion.valor_punto_centavos(db, entorno.ids["otra_empresa"]) == 1000
    entorno.como("cajero")
    assert entorno.http.put("/clientes/regla-puntos", json={"valor_punto_centavos": 1}).status_code == 403
    entorno.como("admin")
    assert entorno.http.put("/clientes/regla-puntos", json={"valor_punto_centavos": 0}).status_code == 422


def test_el_cajero_consulta_el_saldo_de_un_cliente_de_su_empresa(entorno):
    entorno.como("cajero")

    ok = entorno.http.get(f"/clientes/{entorno.ids['cliente']}/puntos")
    ajeno = entorno.http.get(f"/clientes/{entorno.ids['cliente_ajeno']}/puntos")

    assert ok.status_code == 200 and ok.json()["saldo"] == SALDO_INICIAL
    assert ajeno.status_code == 404  # de otra empresa: es como si no existiera


# ---------------------------------------------------------------------------------------------------------------
# Canje al vender
# ---------------------------------------------------------------------------------------------------------------

def test_venta_online_con_canje_baja_el_total_resta_los_puntos_y_deja_el_movimiento(entorno):
    r = entorno.comprar_online(puntos=3)

    assert r.status_code == 201, r.text
    assert r.json()["total"] == 200 - 3 * 10  # 3 puntos × 10 de descuento
    assert entorno.saldo() == SALDO_INICIAL - 3
    with entorno.Sesion() as db:
        [mov] = db.query(MovimientoPuntos).all()
        assert (mov.tipo_operacion, mov.cantidad, mov.cliente_id) == ("PUNTOS_RESTADOS", 3, entorno.ids["cliente"])


def test_sin_puntos_a_canjear_la_venta_no_cambia(entorno):
    r = entorno.comprar_online(puntos=0)

    assert r.status_code == 201 and r.json()["total"] == 200
    assert entorno.saldo() == SALDO_INICIAL and entorno.contar(MovimientoPuntos) == 0


def test_no_se_pueden_canjear_mas_puntos_de_los_que_se_tienen(entorno):
    r = entorno.comprar_online(puntos=SALDO_INICIAL + 1)

    assert r.status_code == 400 and "Puntos insuficientes" in r.json()["detail"]
    assert entorno.saldo() == SALDO_INICIAL  # nada cambió
    assert entorno.contar(Venta) == 0  # y la venta no se guardó
    assert entorno.contar(MovimientoPuntos) == 0


def test_el_descuento_no_puede_ser_mayor_al_total(entorno):
    with entorno.Sesion() as db:  # el cliente tiene muchos puntos: 30 puntos = 300 de descuento > 200 de total
        db.query(PuntosCliente).update({"saldo": 30})
        db.commit()

    r = entorno.comprar_online(puntos=30)

    assert r.status_code == 400 and "no puede ser mayor al total" in r.json()["detail"]
    assert entorno.saldo() == 30 and entorno.contar(Venta) == 0


def test_un_descuento_igual_al_total_si_se_permite(entorno):
    with entorno.Sesion() as db:
        db.query(PuntosCliente).update({"saldo": 20})
        db.commit()

    r = entorno.comprar_online(puntos=20)  # 20 × 10 = 200 = total

    assert r.status_code == 201 and r.json()["total"] == 0
    assert entorno.saldo() == 0


def test_el_canje_usa_la_regla_de_la_empresa(entorno):
    entorno.como("admin")
    entorno.http.put("/clientes/regla-puntos", json={"valor_punto_centavos": 250})  # cada punto vale 2.50

    r = entorno.comprar_online(puntos=4)

    assert r.json()["total"] == 200 - 4 * 2.5


def test_el_cajero_canjea_puntos_del_cliente_en_una_venta_presencial(entorno):
    r = entorno.vender_en_caja(puntos=2)

    assert r.status_code == 201, r.text
    assert r.json()["total"] == 200 - 20
    assert entorno.saldo() == SALDO_INICIAL - 2


def test_canjear_en_caja_exige_un_cliente(entorno):
    r = entorno.vender_en_caja(puntos=2, cliente=None)

    assert r.status_code == 400 and "cliente registrado" in r.json()["detail"]
    assert entorno.contar(Venta) == 0


def test_no_se_canjean_puntos_de_un_cliente_de_otra_empresa(entorno):
    with entorno.Sesion() as db:
        db.add(PuntosCliente(empresa_id=entorno.ids["otra_empresa"], cliente_id=entorno.ids["cliente_ajeno"], saldo=99))
        db.commit()

    r = entorno.vender_en_caja(puntos=1, cliente="cliente_ajeno")

    assert r.status_code == 400 and "Cliente no encontrado" in r.json()["detail"]
    assert entorno.saldo("cliente_ajeno") == 99


def test_un_canje_rechazado_no_deja_stock_descontado(entorno):
    """La venta presencial descuenta stock: si el canje falla no debe quedar nada a medias."""
    entorno.vender_en_caja(puntos=SALDO_INICIAL + 5)

    with entorno.Sesion() as db:
        assert db.query(Inventario).one().cantidad_disponible == 50
    assert entorno.contar(Venta) == 0


# ---------------------------------------------------------------------------------------------------------------
# Cancelación: los puntos vuelven
# ---------------------------------------------------------------------------------------------------------------

def test_si_se_cancela_la_venta_los_puntos_canjeados_vuelven_una_sola_vez(entorno):
    venta_id = entorno.comprar_online(puntos=3).json()["id"]
    assert entorno.saldo() == SALDO_INICIAL - 3

    with entorno.Sesion() as db:
        venta = db.get(Venta, venta_id)
        fidelizacion.devolver_canje_de_venta(db, venta)
        fidelizacion.devolver_canje_de_venta(db, venta)  # reintentar no devuelve dos veces
        db.commit()

    assert entorno.saldo() == SALDO_INICIAL


def test_cancelar_una_venta_sin_canje_no_toca_el_saldo(entorno):
    venta_id = entorno.comprar_online(puntos=0).json()["id"]
    with entorno.Sesion() as db:
        fidelizacion.devolver_canje_de_venta(db, db.get(Venta, venta_id))
        db.commit()

    assert entorno.saldo() == SALDO_INICIAL


# ---------------------------------------------------------------------------------------------------------------
# Venta offline (móvil): el descuento va en la venta y los puntos salen con PUNTOS_RESTADOS ("canje")
# ---------------------------------------------------------------------------------------------------------------

def _lote_offline(entorno, puntos: int, uuid="v-offline"):
    return {
        "operaciones": [{
            "uuid": uuid, "tipo_operacion": "VENTA_CONTADO", "sucursal_id": entorno.ids["sucursal"], "cajero_id": entorno.ids["cajero"],
            "cliente_id": entorno.ids["cliente"], "puntos_canjeados": puntos, "items": entorno.items(2),
        }],
    }


def _canje_offline(entorno, cantidad: int, uuid="p-canje", venta="v-offline"):
    return {"movimientos_puntos": [{
        "uuid": uuid, "tipo_operacion": "PUNTOS_RESTADOS", "cliente_id": entorno.ids["cliente"], "cantidad": cantidad,
        "operacion_uuid": venta, "venta_uuid": venta, "motivo": "canje",
    }]}


def test_venta_offline_con_canje_lleva_el_descuento_y_luego_resta_los_puntos(entorno):
    entorno.como("cajero")
    venta = entorno.http.post("/sync/operaciones", json=_lote_offline(entorno, puntos=3)).json()["resultados"][0]
    assert venta["status"] == "ok"
    assert float(entorno.venta(venta["id_servidor"]).total) == 200 - 30

    canje = entorno.http.post("/sync/operaciones", json=_canje_offline(entorno, 3)).json()["resultados"][0]

    assert canje["status"] == "ok"
    assert entorno.saldo() == SALDO_INICIAL - 3


def test_un_canje_offline_no_puede_gastar_mas_de_lo_que_el_cliente_tiene(entorno):
    entorno.como("cajero")
    entorno.http.post("/sync/operaciones", json=_lote_offline(entorno, puntos=1))

    canje = entorno.http.post("/sync/operaciones", json=_canje_offline(entorno, SALDO_INICIAL + 4)).json()["resultados"][0]

    assert canje["status"] == "conflict" and "Puntos insuficientes" in canje["message"]
    assert entorno.saldo() == SALDO_INICIAL  # no se recortó a cero ni se restó nada


def test_venta_offline_cuyo_descuento_supera_el_total_se_rechaza(entorno):
    entorno.como("cajero")

    r = entorno.http.post("/sync/operaciones", json=_lote_offline(entorno, puntos=21)).json()["resultados"][0]  # 21 × 10 > 200

    assert r["status"] == "conflict" and "descuento por puntos" in r["message"]
    assert entorno.contar(Venta) == 0


def test_el_canje_offline_sin_la_marca_motivo_sigue_recortando_a_cero_como_antes(entorno):
    """Compatibilidad: las restas por devolución (sin `motivo`) no cambian."""
    entorno.como("cajero")
    entorno.http.post("/sync/operaciones", json=_lote_offline(entorno, puntos=0))
    lote = _canje_offline(entorno, SALDO_INICIAL + 4)
    del lote["movimientos_puntos"][0]["motivo"]

    r = entorno.http.post("/sync/operaciones", json=lote).json()["resultados"][0]

    assert r["status"] == "ok" and entorno.saldo() == 0
