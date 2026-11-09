"""Reembolsos: devolución de DINERO de un pedido (reserva o venta) cancelado, con el QR bancario del cliente.

- El cliente pide el reembolso de SU pedido cancelado (idempotente) y sube su QR: solo el dueño, con imagen válida (PNG/JPG/WEBP).
- El personal (cajero / encargado / administrador) ve el QR y marca el reembolso: el pedido pasa a `reembolsada`.
- Multi-empresa: el pedido o reembolso de otra empresa, de otro cliente o de otra sucursal (para cajero) no existe.
- Sincronización móvil: `qr_devoluciones` aplica las mismas reglas y es idempotente por uuid.

Usa SQLite en memoria y un directorio temporal (no toca ninguna base ni carpeta real). Ejecutar desde `backend/`:  python -m pytest app/modules -v
"""
import base64
import os

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.modules.auth.service import get_current_user
from app.modules.catalogo.models import Categoria, Color, Producto, Talla
from app.modules.devoluciones.models import Reembolso
from app.modules.empresas.models import Empresa
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import SyncOperacion
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta
from app.shared.core.config import settings
from app.shared.db.session import Base, get_db

PNG = b"\x89PNG\r\n\x1a\n" + b"qr-bancario" * 20
JPG = b"\xff\xd8\xff\xe0" + b"qr-bancario" * 20


class Entorno:
    def __init__(self, client, Sesion, ids, actual, carpeta):
        self.http, self.Sesion, self.ids, self._actual, self.carpeta = client, Sesion, ids, actual, carpeta

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def archivos_qr(self) -> list[str]:
        destino = os.path.join(self.carpeta, "qr_devolucion")
        return sorted(os.listdir(destino)) if os.path.isdir(destino) else []

    def reembolso(self, **filtro) -> Reembolso | None:
        with self.Sesion() as db:
            r = db.query(Reembolso).filter_by(**filtro).first()
            if r is not None:
                db.expunge(r)
            return r

    def estado_de(self, modelo, id_) -> str:
        with self.Sesion() as db:
            return db.get(modelo, id_).estado

    def pedir(self, quien="cliente", **origen):
        self.como(quien)
        return self.http.post("/devoluciones/reembolsos", json=origen)

    def subir(self, reembolso_id, quien="cliente", contenido=PNG, nombre="qr.png"):
        self.como(quien)
        return self.http.post(f"/devoluciones/{reembolso_id}/qr", files={"archivo": (nombre, contenido, "image/png")})

    def procesar(self, quien="cajero", **origen):
        self.como(quien)
        return self.http.post("/devoluciones/reembolsos/procesar", json=origen)

    def sync_qr(self, uuid, quien="cliente", imagen=PNG, **origen):
        self.como(quien)
        cuerpo = {"qr_devoluciones": [{"uuid": uuid, "imagen_base64": base64.b64encode(imagen).decode(), **origen}]}
        r = self.http.post("/sync/operaciones", json=cuerpo)
        assert r.status_code == 200, r.text
        return r.json()["resultados"][0]


@pytest.fixture()
def entorno(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "uploads_dir", str(tmp_path))
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
    talla, color = Talla(empresa_id=empresa.id, nombre="M"), Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([suc_a, suc_b, suc_otra, cat, talla, color])
    db.flush()
    camisa = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=cat.id)
    usuarios = {
        "cajero": Usuario(nombre="Cajero A", email="a@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "cajero_b": Usuario(nombre="Cajero B", email="b@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_b.id),
        "encargado": Usuario(nombre="Encargado A", email="e@t.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "admin": Usuario(nombre="Admin", email="ad@t.bo", rol="administrador", empresa_id=empresa.id),
        "admin_ajeno": Usuario(nombre="Admin Ajeno", email="x@o.bo", rol="administrador", empresa_id=otra.id),
        "cliente": Usuario(nombre="Cliente Uno", email="c1@t.bo", rol="cliente", empresa_id=empresa.id),
        "cliente2": Usuario(nombre="Cliente Dos", email="c2@t.bo", rol="cliente", empresa_id=empresa.id),
        "cliente_ajeno": Usuario(nombre="Cliente Ajeno", email="c3@o.bo", rol="cliente", empresa_id=otra.id),
    }
    db.add_all([camisa, *usuarios.values()])
    db.flush()

    def reserva(cliente, sucursal, estado):
        r = Reserva(cliente_id=usuarios[cliente].id, sucursal_id=sucursal.id, estado=estado)
        db.add(r)
        db.flush()
        db.add(ReservaItem(reserva_id=r.id, producto_id=camisa.id, talla_id=talla.id, color_id=color.id, cantidad=2))
        db.flush()
        return r

    r_cancelada = reserva("cliente", suc_a, "cancelada")  # 2 x $100 = $200
    r_pendiente = reserva("cliente", suc_a, "pendiente")
    r_cancelada_2 = reserva("cliente2", suc_a, "cancelada")
    r_en_b = reserva("cliente", suc_b, "cancelada")  # de otra sucursal
    v_cancelada = Venta(cliente_id=usuarios["cliente"].id, sucursal_id=suc_a.id, canal="online", estado="cancelada", total=150)
    v_anonima = Venta(cliente_id=None, sucursal_id=suc_a.id, canal="presencial", estado="cancelada", total=80)
    v_completada = Venta(cliente_id=usuarios["cliente"].id, sucursal_id=suc_a.id, canal="online", estado="completada", total=60)
    db.add_all([v_cancelada, v_anonima, v_completada])
    db.commit()
    ids = {
        "suc_a": suc_a.id, "suc_b": suc_b.id, **{k: u.id for k, u in usuarios.items()},
        "r_cancelada": r_cancelada.id, "r_pendiente": r_pendiente.id, "r_cancelada_2": r_cancelada_2.id, "r_en_b": r_en_b.id,
        "v_cancelada": v_cancelada.id, "v_anonima": v_anonima.id, "v_completada": v_completada.id,
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
        yield Entorno(TestClient(app), Sesion, ids, actual, str(tmp_path))
    finally:
        app.dependency_overrides.clear()
        engine.dispose()


# ---------------------------------------------------------------------------------------------------------------
# El cliente pide el reembolso de su pedido cancelado
# ---------------------------------------------------------------------------------------------------------------

def test_el_cliente_pide_el_reembolso_de_su_reserva_cancelada_y_es_idempotente(entorno):
    r = entorno.pedir(reserva_id=entorno.ids["r_cancelada"])

    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["estado"] == "pendiente"
    assert cuerpo["reserva_id"] == entorno.ids["r_cancelada"] and cuerpo["venta_id"] is None
    assert cuerpo["monto"] == 200.0 and cuerpo["tiene_qr"] is False and cuerpo["qr_devolucion_url"] is None

    otra_vez = entorno.pedir(reserva_id=entorno.ids["r_cancelada"])
    assert otra_vez.status_code == 200 and otra_vez.json()["id"] == cuerpo["id"]
    with entorno.Sesion() as db:
        assert db.query(Reembolso).count() == 1


def test_hay_que_indicar_la_reserva_o_la_venta_pero_no_las_dos(entorno):
    assert entorno.pedir().status_code == 422
    assert entorno.pedir(reserva_id=entorno.ids["r_cancelada"], venta_id=entorno.ids["v_cancelada"]).status_code == 422


def test_solo_se_reembolsa_un_pedido_cancelado(entorno):
    r = entorno.pedir(reserva_id=entorno.ids["r_pendiente"])
    assert r.status_code == 400
    assert "cancelado" in r.json()["detail"]
    r = entorno.pedir(venta_id=entorno.ids["v_completada"])
    assert r.status_code == 400
    with entorno.Sesion() as db:
        assert db.query(Reembolso).count() == 0


def test_el_pedido_de_otro_cliente_o_de_otra_empresa_no_existe(entorno):
    assert entorno.pedir("cliente2", reserva_id=entorno.ids["r_cancelada"]).status_code == 404
    assert entorno.pedir("cliente_ajeno", reserva_id=entorno.ids["r_cancelada"]).status_code == 404
    assert entorno.pedir("cliente2", venta_id=entorno.ids["v_cancelada"]).status_code == 404
    with entorno.Sesion() as db:
        assert db.query(Reembolso).count() == 0


def test_el_personal_no_puede_pedir_el_reembolso_como_cliente(entorno):
    assert entorno.pedir("cajero", reserva_id=entorno.ids["r_cancelada"]).status_code == 403


# ---------------------------------------------------------------------------------------------------------------
# QR bancario del cliente
# ---------------------------------------------------------------------------------------------------------------

def test_el_cliente_sube_su_qr_y_queda_guardado_con_su_url(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]

    r = entorno.subir(rid)

    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["tiene_qr"] is True and cuerpo["estado"] == "pendiente"
    assert f"/uploads/qr_devolucion/reembolso_{rid}_" in cuerpo["qr_devolucion_url"]
    assert cuerpo["qr_devolucion_url"].endswith(".png")
    assert cuerpo["qr_subido_en"] is not None
    (archivo,) = entorno.archivos_qr()
    with open(os.path.join(entorno.carpeta, "qr_devolucion", archivo), "rb") as f:
        assert f.read() == PNG


def test_un_archivo_que_no_es_imagen_se_rechaza_aunque_diga_ser_png(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]

    r = entorno.subir(rid, contenido=b"esto no es una imagen", nombre="qr.png")

    assert r.status_code == 400
    assert "imagen" in r.json()["detail"].lower()
    assert entorno.archivos_qr() == []
    assert entorno.reembolso(id=rid).tiene_qr is False


def test_un_qr_vacio_o_demasiado_grande_se_rechaza(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    assert entorno.subir(rid, contenido=b"").status_code == 400
    grande = b"\x89PNG\r\n\x1a\n" + b"0" * (5 * 1024 * 1024 + 10)
    assert entorno.subir(rid, contenido=grande).status_code == 400
    assert entorno.archivos_qr() == []


def test_solo_el_dueno_del_reembolso_sube_el_qr(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]

    assert entorno.subir(rid, "cliente2").status_code == 404  # otro cliente de la misma empresa
    assert entorno.subir(rid, "cliente_ajeno").status_code == 404  # un cliente de otra empresa
    assert entorno.subir(rid, "cajero").status_code == 403  # el personal no sube el QR del cliente
    assert entorno.subir(999999).status_code == 404
    assert entorno.archivos_qr() == []


def test_cambiar_el_qr_reemplaza_la_imagen_y_borra_la_anterior(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    entorno.subir(rid, contenido=PNG)
    (primero,) = entorno.archivos_qr()

    r = entorno.subir(rid, contenido=JPG, nombre="otro.jpg")

    assert r.status_code == 200 and r.json()["qr_devolucion_url"].endswith(".jpg")
    (segundo,) = entorno.archivos_qr()
    assert segundo != primero and segundo.endswith(".jpg")


# ---------------------------------------------------------------------------------------------------------------
# El personal ve el QR y procesa el reembolso
# ---------------------------------------------------------------------------------------------------------------

def test_el_encargado_ve_el_qr_en_las_reservas_de_su_sucursal(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    url = entorno.subir(rid).json()["qr_devolucion_url"]

    entorno.como("encargado")
    reservas = {r["id"]: r for r in entorno.http.get("/reservas/mi-sucursal").json()}

    cancelada = reservas[entorno.ids["r_cancelada"]]
    assert cancelada["estado"] == "cancelada"
    assert cancelada["reembolso"]["id"] == rid
    assert cancelada["reembolso"]["qr_devolucion_url"] == url
    assert cancelada["reembolso"]["monto"] == 200.0
    # una reserva sin reembolso (o la de otro cliente aún sin pedirlo) no trae nada
    assert reservas[entorno.ids["r_pendiente"]]["reembolso"] is None
    assert reservas[entorno.ids["r_cancelada_2"]]["reembolso"] is None


def test_el_cliente_ve_su_reembolso_en_mis_reservas(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    entorno.subir(rid)

    entorno.como("cliente")
    mis = {r["id"]: r for r in entorno.http.get("/reservas/mis-reservas").json()}

    assert mis[entorno.ids["r_cancelada"]]["reembolso"]["tiene_qr"] is True
    assert mis[entorno.ids["r_pendiente"]]["reembolso"] is None


def test_procesar_el_reembolso_deja_el_pedido_reembolsado_y_no_se_repite(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    entorno.subir(rid)

    r = entorno.procesar("cajero", reserva_id=entorno.ids["r_cancelada"])

    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert cuerpo["id"] == rid and cuerpo["estado"] == "reembolsado" and cuerpo["procesado_en"] is not None
    assert cuerpo["origen"] == "reserva" and cuerpo["nombre_cliente"] == "Cliente Uno" and cuerpo["tiene_qr"] is True
    assert entorno.estado_de(Reserva, entorno.ids["r_cancelada"]) == "reembolsada"
    assert entorno.reembolso(id=rid).procesado_por_id == entorno.ids["cajero"]

    assert entorno.procesar("cajero", reserva_id=entorno.ids["r_cancelada"]).status_code == 409  # ya reembolsada

    entorno.como("encargado")
    reservas = {r["id"]: r for r in entorno.http.get("/reservas/mi-sucursal").json()}
    assert reservas[entorno.ids["r_cancelada"]]["estado"] == "reembolsada"
    assert reservas[entorno.ids["r_cancelada"]]["reembolso"]["estado"] == "reembolsado"


def test_se_puede_procesar_aunque_el_cliente_no_haya_pedido_ni_subido_su_qr(entorno):
    r = entorno.procesar("encargado", reserva_id=entorno.ids["r_cancelada_2"])

    assert r.status_code == 200, r.text
    assert r.json()["tiene_qr"] is False and r.json()["monto"] == 200.0
    assert entorno.estado_de(Reserva, entorno.ids["r_cancelada_2"]) == "reembolsada"
    assert entorno.reembolso(reserva_id=entorno.ids["r_cancelada_2"]).cliente_id == entorno.ids["cliente2"]


def test_solo_se_procesa_un_pedido_cancelado(entorno):
    assert entorno.procesar("cajero", reserva_id=entorno.ids["r_pendiente"]).status_code == 400
    assert entorno.procesar("cajero", venta_id=entorno.ids["v_completada"]).status_code == 400
    assert entorno.estado_de(Reserva, entorno.ids["r_pendiente"]) == "pendiente"


def test_procesar_respeta_la_empresa_y_la_sucursal(entorno):
    assert entorno.procesar("admin_ajeno", reserva_id=entorno.ids["r_cancelada"]).status_code == 404  # otra empresa
    assert entorno.procesar("cajero_b", reserva_id=entorno.ids["r_cancelada"]).status_code == 404  # otra sucursal
    assert entorno.procesar("cajero", reserva_id=entorno.ids["r_en_b"]).status_code == 404
    assert entorno.procesar("cliente", reserva_id=entorno.ids["r_cancelada"]).status_code == 403  # un cliente no procesa
    assert entorno.estado_de(Reserva, entorno.ids["r_cancelada"]) == "cancelada"
    # el administrador de la empresa sí puede con cualquier sucursal
    assert entorno.procesar("admin", reserva_id=entorno.ids["r_en_b"]).status_code == 200


def test_despues_de_reembolsado_ya_no_se_cambia_el_qr_ni_el_estado_de_la_reserva(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]
    entorno.procesar("cajero", reserva_id=entorno.ids["r_cancelada"])

    assert entorno.subir(rid).status_code == 409
    assert entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).status_code == 409  # el pedido ya es "reembolsada"
    entorno.como("encargado")
    r = entorno.http.patch(f"/reservas/{entorno.ids['r_cancelada']}/estado", params={"nuevo_estado": "confirmada"})
    assert r.status_code == 400
    entorno.como("cliente")
    assert entorno.http.patch(f"/reservas/{entorno.ids['r_cancelada']}/cancelar").status_code == 400


# ---------------------------------------------------------------------------------------------------------------
# Ventas canceladas (el mismo flujo)
# ---------------------------------------------------------------------------------------------------------------

def test_el_reembolso_de_una_venta_cancelada_sigue_el_mismo_flujo(entorno):
    r = entorno.pedir(venta_id=entorno.ids["v_cancelada"])
    assert r.status_code == 200, r.text
    rid = r.json()["id"]
    assert r.json()["venta_id"] == entorno.ids["v_cancelada"] and r.json()["monto"] == 150.0
    assert entorno.subir(rid).status_code == 200

    p = entorno.procesar("cajero", venta_id=entorno.ids["v_cancelada"])

    assert p.status_code == 200 and p.json()["origen"] == "venta" and p.json()["tiene_qr"] is True
    assert entorno.estado_de(Venta, entorno.ids["v_cancelada"]) == "reembolsada"


def test_una_venta_de_mostrador_sin_cliente_se_reembolsa_sin_qr(entorno):
    r = entorno.procesar("cajero", venta_id=entorno.ids["v_anonima"])

    assert r.status_code == 200, r.text
    assert r.json()["cliente_id"] is None and r.json()["tiene_qr"] is False and r.json()["monto"] == 80.0
    assert entorno.estado_de(Venta, entorno.ids["v_anonima"]) == "reembolsada"


# ---------------------------------------------------------------------------------------------------------------
# Listados
# ---------------------------------------------------------------------------------------------------------------

def test_cada_cliente_ve_solo_sus_reembolsos(entorno):
    entorno.pedir("cliente", reserva_id=entorno.ids["r_cancelada"])
    entorno.pedir("cliente2", reserva_id=entorno.ids["r_cancelada_2"])

    entorno.como("cliente")
    mios = entorno.http.get("/devoluciones/mis-reembolsos").json()
    assert [r["reserva_id"] for r in mios] == [entorno.ids["r_cancelada"]]
    entorno.como("cliente_ajeno")
    assert entorno.http.get("/devoluciones/mis-reembolsos").json() == []
    entorno.como("cajero")
    assert entorno.http.get("/devoluciones/mis-reembolsos").status_code == 403


def test_el_personal_lista_los_reembolsos_de_su_alcance(entorno):
    entorno.pedir("cliente", reserva_id=entorno.ids["r_cancelada"])
    entorno.pedir("cliente", reserva_id=entorno.ids["r_en_b"])
    entorno.procesar("admin", reserva_id=entorno.ids["r_cancelada_2"])

    def ids_de(quien, **params):
        entorno.como(quien)
        r = entorno.http.get("/devoluciones/reembolsos", params=params)
        assert r.status_code == 200, r.text
        return sorted(x["reserva_id"] for x in r.json())

    assert ids_de("admin") == sorted([entorno.ids["r_cancelada"], entorno.ids["r_en_b"], entorno.ids["r_cancelada_2"]])
    assert ids_de("cajero") == sorted([entorno.ids["r_cancelada"], entorno.ids["r_cancelada_2"]])  # solo su sucursal (Centro)
    assert ids_de("cajero_b") == [entorno.ids["r_en_b"]]
    assert ids_de("admin", estado="pendiente") == sorted([entorno.ids["r_cancelada"], entorno.ids["r_en_b"]])
    assert ids_de("admin", estado="reembolsado") == [entorno.ids["r_cancelada_2"]]
    assert ids_de("admin_ajeno") == []  # otra empresa
    entorno.como("cliente")
    assert entorno.http.get("/devoluciones/reembolsos").status_code == 403


# ---------------------------------------------------------------------------------------------------------------
# Sincronización móvil: tipo SUBIR_QR_DEVOLUCION (lista `qr_devoluciones` del lote)
# ---------------------------------------------------------------------------------------------------------------

def test_la_sincronizacion_sube_el_qr_y_crea_el_reembolso_si_no_existia(entorno):
    r = entorno.sync_qr("cola-1", reserva_id=entorno.ids["r_cancelada"])

    assert r["status"] == "ok" and r["entidad"] == "reembolso"
    reembolso = entorno.reembolso(reserva_id=entorno.ids["r_cancelada"])
    assert r["id_servidor"] == reembolso.id and reembolso.tiene_qr and reembolso.cliente_id == entorno.ids["cliente"]
    assert len(entorno.archivos_qr()) == 1


def test_la_sincronizacion_es_idempotente_por_uuid(entorno):
    primera = entorno.sync_qr("cola-1", reserva_id=entorno.ids["r_cancelada"])
    repetida = entorno.sync_qr("cola-1", reserva_id=entorno.ids["r_cancelada"], imagen=JPG)  # reintento tras un corte de red

    assert repetida == primera
    assert len(entorno.archivos_qr()) == 1
    with entorno.Sesion() as db:
        assert db.query(Reembolso).count() == 1
        assert db.query(SyncOperacion).filter_by(tipo_operacion="SUBIR_QR_DEVOLUCION").count() == 1


def test_la_sincronizacion_usa_el_reembolso_que_ya_se_habia_pedido(entorno):
    rid = entorno.pedir(reserva_id=entorno.ids["r_cancelada"]).json()["id"]

    r = entorno.sync_qr("cola-1", reserva_id=entorno.ids["r_cancelada"])

    assert r["status"] == "ok" and r["id_servidor"] == rid
    with entorno.Sesion() as db:
        assert db.query(Reembolso).count() == 1


def test_la_sincronizacion_funciona_tambien_con_una_venta_cancelada(entorno):
    r = entorno.sync_qr("cola-v", venta_id=entorno.ids["v_cancelada"])
    assert r["status"] == "ok"
    assert entorno.reembolso(venta_id=entorno.ids["v_cancelada"]).tiene_qr is True


@pytest.mark.parametrize("caso", ["base64_invalido", "no_es_imagen", "pedido_ajeno", "otra_empresa", "no_cancelado", "ya_reembolsado", "sin_pedido", "no_es_cliente"])
def test_la_sincronizacion_rechaza_lo_que_no_se_puede_aplicar(entorno, caso):
    ids = entorno.ids
    if caso == "ya_reembolsado":
        entorno.procesar("cajero", reserva_id=ids["r_cancelada"])
    entorno.como("cliente")
    quien, origen, imagen = "cliente", {"reserva_id": ids["r_cancelada"]}, PNG
    if caso == "no_es_imagen":
        imagen = b"texto cualquiera"
    elif caso == "pedido_ajeno":
        quien = "cliente2"
    elif caso == "otra_empresa":
        quien = "cliente_ajeno"
    elif caso == "no_cancelado":
        origen = {"reserva_id": ids["r_pendiente"]}
    elif caso == "sin_pedido":
        origen = {}
    elif caso == "no_es_cliente":
        quien = "cajero"

    if caso == "base64_invalido":
        entorno.como("cliente")
        cuerpo = {"qr_devoluciones": [{"uuid": "x", "reserva_id": ids["r_cancelada"], "imagen_base64": "###no-es-base64###"}]}
        r = entorno.http.post("/sync/operaciones", json=cuerpo).json()["resultados"][0]
    else:
        r = entorno.sync_qr("x", quien, imagen, **origen)

    assert r["status"] == "conflict" and r["message"], caso
    assert entorno.archivos_qr() == []
    reembolso = entorno.reembolso(reserva_id=ids["r_cancelada"])
    assert reembolso is None or not reembolso.tiene_qr
