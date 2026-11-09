"""Compra offline del cliente con pago QR y comprobante (VENTA_CLIENTE_QR).

- Sincronización: el comprobante viaja en base64 en el lote. La venta queda `pendiente` (online) y su pago QR en
  `pendiente_verificacion`; el stock NO se toca hasta que el personal apruebe. Es idempotente por uuid.
- "Pagos por verificar": aparecen estas compras (y siguen apareciendo los pagos QR de la web), con la URL del comprobante.
- `POST /pagos/{id}/verificar`: APROBAR descuenta el stock y completa la venta; RECHAZAR cancela la venta y crea un reembolso
  pendiente que el cliente cobra adjuntando su QR. Sin stock al aprobar: se cancela y también queda el reembolso.
- Multi-empresa: lo de otra empresa no existe; un cajero o encargado solo verifica pagos de su sucursal.

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
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.pagos.models import Pago
from app.modules.reservas.models import Reserva
from app.modules.sucursales.models import Sucursal
from app.modules.sync.models import SyncOperacion
from app.modules.usuarios.models import Usuario
from app.modules.ventas.models import Venta, VentaItem
from app.shared.core.config import settings
from app.shared.db.session import Base, get_db

PNG = b"\x89PNG\r\n\x1a\n" + b"comprobante" * 20
STOCK = 10


class Entorno:
    def __init__(self, client, Sesion, ids, actual, carpeta):
        self.http, self.Sesion, self.ids, self._actual, self.carpeta = client, Sesion, ids, actual, carpeta

    def como(self, quien: str):
        self._actual["id"] = self.ids[quien]

    def comprobantes(self) -> list[str]:
        destino = os.path.join(self.carpeta, "comprobantes")
        return sorted(os.listdir(destino)) if os.path.isdir(destino) else []

    def stock(self) -> int:
        with self.Sesion() as db:
            return db.get(Inventario, self.ids["inv"]).cantidad_disponible

    def poner_stock(self, cantidad: int):
        with self.Sesion() as db:
            db.get(Inventario, self.ids["inv"]).cantidad_disponible = cantidad
            db.commit()

    def contar(self, modelo) -> int:
        with self.Sesion() as db:
            return db.query(modelo).count()

    def obtener(self, modelo, **filtro):
        with self.Sesion() as db:
            fila = db.query(modelo).filter_by(**filtro).first()
            if fila is not None:
                db.expunge(fila)
            return fila

    def item(self, cantidad=2, **extra):
        return {"producto_id": self.ids["camisa"], "talla_id": self.ids["talla"], "color_id": self.ids["color"], "cantidad": cantidad,
                "precio_unitario_centavos": 1, **extra}

    def operacion(self, uuid, tipo="VENTA_CLIENTE_QR", comprobante=PNG, **extra):
        op = {"uuid": uuid, "tipo_operacion": tipo, "sucursal_id": self.ids["suc_a"], "items": [self.item()], **extra}
        if comprobante is not None:
            op["comprobante_base64"] = base64.b64encode(comprobante).decode()
            op["comprobante_nombre"] = "comprobante.png"
        return op

    def sync(self, operaciones, quien="cliente"):
        self.como(quien)
        r = self.http.post("/sync/operaciones", json={"operaciones": operaciones})
        assert r.status_code == 200, r.text
        return r.json()["resultados"]

    def comprar(self, uuid="compra-1", quien="cliente", **kw) -> dict:
        return self.sync([self.operacion(uuid, **kw)], quien)[0]

    def pago_de(self, venta_id: int) -> Pago:
        return self.obtener(Pago, venta_id=venta_id)

    def pendientes(self, quien="cajero"):
        self.como(quien)
        return self.http.get("/pagos/pendientes-verificacion")

    def verificar(self, pago_id, accion, quien="cajero", motivo=None):
        self.como(quien)
        cuerpo = {"accion": accion, **({"motivo": motivo} if motivo else {})}
        return self.http.post(f"/pagos/{pago_id}/verificar", json=cuerpo)

    def comprar_y_obtener(self, uuid="compra-1") -> tuple[int, int]:
        r = self.comprar(uuid)
        assert r["status"] == "ok", r
        return r["id_servidor"], self.pago_de(r["id_servidor"]).id


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
    cat, cat_otra = Categoria(empresa_id=empresa.id, nombre="Ropa"), Categoria(empresa_id=otra.id, nombre="Otra ropa")
    talla, color = Talla(empresa_id=empresa.id, nombre="M"), Color(empresa_id=empresa.id, nombre="Negro")
    db.add_all([suc_a, suc_b, suc_otra, cat, cat_otra, talla, color])
    db.flush()
    camisa = Producto(empresa_id=empresa.id, nombre="Camisa Oxford", precio=100, categoria_id=cat.id)
    ajeno = Producto(empresa_id=otra.id, nombre="Producto ajeno", precio=50, categoria_id=cat_otra.id)
    usuarios = {
        "cajero": Usuario(nombre="Cajero A", email="a@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "cajero_b": Usuario(nombre="Cajero B", email="b@t.bo", rol="cajero", empresa_id=empresa.id, sucursal_id=suc_b.id),
        "encargado": Usuario(nombre="Encargado A", email="e@t.bo", rol="encargado_sucursal", empresa_id=empresa.id, sucursal_id=suc_a.id),
        "admin": Usuario(nombre="Admin", email="ad@t.bo", rol="administrador", empresa_id=empresa.id),
        "admin_ajeno": Usuario(nombre="Admin Ajeno", email="x@o.bo", rol="administrador", empresa_id=otra.id),
        "cliente": Usuario(nombre="Cliente Uno", email="c1@t.bo", rol="cliente", empresa_id=empresa.id),
        "cliente2": Usuario(nombre="Cliente Dos", email="c2@t.bo", rol="cliente", empresa_id=empresa.id),
    }
    db.add_all([camisa, ajeno, *usuarios.values()])
    db.flush()
    inventario = Inventario(producto_id=camisa.id, sucursal_id=suc_a.id, talla_id=talla.id, color_id=color.id, cantidad_disponible=STOCK)
    db.add(inventario)
    db.commit()
    ids = {
        "suc_a": suc_a.id, "suc_b": suc_b.id, "suc_otra": suc_otra.id, "camisa": camisa.id, "ajeno": ajeno.id,
        "talla": talla.id, "color": color.id, "inv": inventario.id, **{k: u.id for k, u in usuarios.items()},
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
# Sincronización: VENTA_CLIENTE_QR con el comprobante en base64
# ---------------------------------------------------------------------------------------------------------------

def test_la_compra_offline_se_guarda_pendiente_con_su_comprobante_y_sin_tocar_el_stock(entorno):
    r = entorno.comprar("compra-1")

    assert r["status"] == "ok" and r["entidad"] == "venta"
    venta = entorno.obtener(Venta, id=r["id_servidor"])
    assert (venta.estado, venta.canal, venta.cliente_id) == ("pendiente", "online", entorno.ids["cliente"])
    assert float(venta.total) == 200.0, "el total sale del precio del servidor, no del que mandó la app"
    with entorno.Sesion() as db:
        (item,) = db.query(VentaItem).filter_by(venta_id=venta.id).all()
        assert (item.cantidad, float(item.precio_unitario)) == (2, 100.0)
    pago = entorno.pago_de(venta.id)
    assert (pago.metodo, pago.estado, float(pago.monto)) == ("qr", "pendiente_verificacion", 200.0)
    assert pago.comprobante_path and pago.comprobante_path.startswith("comprobantes/pago_")
    (archivo,) = entorno.comprobantes()
    with open(os.path.join(entorno.carpeta, "comprobantes", archivo), "rb") as f:
        assert f.read() == PNG  # lo que viajó en base64 es lo que se guardó
    assert entorno.stock() == STOCK, "el stock real no baja hasta que el personal apruebe"
    assert entorno.contar(MovimientoInventario) == 0


def test_la_sincronizacion_es_idempotente_por_uuid(entorno):
    primera = entorno.comprar("compra-1")
    repetida = entorno.comprar("compra-1")  # reintento tras un corte de red

    assert repetida == primera
    assert (entorno.contar(Venta), entorno.contar(Pago), len(entorno.comprobantes())) == (1, 1, 1)
    with entorno.Sesion() as db:
        assert db.query(SyncOperacion).filter_by(tipo_operacion="VENTA_CLIENTE_QR").count() == 1


@pytest.mark.parametrize("caso", ["no_es_cliente", "cliente_ajeno", "sin_comprobante", "base64_invalido", "no_es_imagen", "producto_de_otra_empresa", "sucursal_de_otra_empresa", "sin_items", "cantidad_invalida"])
def test_la_sincronizacion_rechaza_lo_que_no_se_puede_aplicar(entorno, caso):
    quien, kw = "cliente", {}
    if caso == "no_es_cliente":
        quien = "cajero"
    elif caso == "cliente_ajeno":
        kw["cliente_id"] = entorno.ids["cliente2"]
    elif caso == "sin_comprobante":
        kw["comprobante"] = None
    elif caso == "no_es_imagen":
        kw["comprobante"] = b"esto no es una imagen"
    elif caso == "producto_de_otra_empresa":
        kw["items"] = [entorno.item(producto_id=entorno.ids["ajeno"])]
    elif caso == "sucursal_de_otra_empresa":
        kw["sucursal_id"] = entorno.ids["suc_otra"]
    elif caso == "sin_items":
        kw["items"] = []
    elif caso == "cantidad_invalida":
        kw["items"] = [entorno.item(cantidad=0)]

    op = entorno.operacion("x", **kw)
    if caso == "base64_invalido":
        op["comprobante_base64"] = "###no-es-base64###"
    r = entorno.sync([op], quien)[0]

    assert r["status"] == "conflict" and r["message"], caso
    assert (entorno.contar(Venta), entorno.contar(Pago), entorno.comprobantes()) == (0, 0, []), caso


def test_una_reserva_y_una_compra_offline_en_el_mismo_lote_siguen_su_propio_camino(entorno):
    resultados = entorno.sync([
        entorno.operacion("res-1", tipo="RESERVA_CLIENTE", comprobante=None, items=[entorno.item(cantidad=1)]),
        entorno.operacion("compra-1"),
    ])

    assert [(r["status"], r["entidad"]) for r in resultados] == [("ok", "reserva"), ("ok", "venta")]
    assert entorno.contar(Reserva) == 1, "la reserva sigue siendo una reserva (sin pago ni comprobante)"
    assert (entorno.contar(Venta), entorno.contar(Pago)) == (1, 1)


# ---------------------------------------------------------------------------------------------------------------
# "Pagos por verificar"
# ---------------------------------------------------------------------------------------------------------------

def test_la_compra_offline_aparece_en_pagos_por_verificar_con_su_comprobante(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()

    r = entorno.pendientes("cajero")

    assert r.status_code == 200, r.text
    (pago,) = r.json()
    assert pago["id"] == pago_id and pago["venta_id"] == venta_id and pago["estado"] == "pendiente_verificacion"
    assert pago["monto"] == 200.0 and pago["comprobante_url"].endswith(".png") and "/uploads/comprobantes/" in pago["comprobante_url"]
    assert [p["id"] for p in entorno.pendientes("encargado").json()] == [pago_id]
    assert [p["id"] for p in entorno.pendientes("admin").json()] == [pago_id]


def test_pagos_por_verificar_respeta_la_empresa_y_la_sucursal(entorno):
    entorno.comprar_y_obtener()

    assert entorno.pendientes("cajero_b").json() == []  # el cajero de otra sucursal no lo ve
    assert entorno.pendientes("admin_ajeno").json() == []  # ni otra empresa
    assert entorno.pendientes("cliente").status_code == 403


def _pago_qr_de_la_web(entorno) -> int:
    """Un pago QR de una compra online hecha EN LÍNEA: queda `pendiente` con su comprobante."""
    with entorno.Sesion() as db:
        venta = Venta(cliente_id=entorno.ids["cliente2"], sucursal_id=entorno.ids["suc_a"], canal="online", estado="pendiente", total=100)
        db.add(venta)
        db.flush()
        db.add(VentaItem(venta_id=venta.id, producto_id=entorno.ids["camisa"], talla_id=entorno.ids["talla"], color_id=entorno.ids["color"], cantidad=1, precio_unitario=100))
        pago = Pago(venta_id=venta.id, metodo="qr", monto=100, estado="pendiente", comprobante_path="comprobantes/web.png")
        db.add(pago)
        db.commit()
        return pago.id


def test_los_pagos_qr_de_la_web_siguen_apareciendo_y_se_confirman_como_siempre(entorno):
    web = _pago_qr_de_la_web(entorno)
    _, offline = entorno.comprar_y_obtener()

    assert sorted(p["id"] for p in entorno.pendientes("cajero").json()) == sorted([web, offline])
    entorno.como("cajero")
    r = entorno.http.patch(f"/pagos/{web}/confirmar-qr", json={"aprobar": True})  # el endpoint de siempre
    assert r.status_code == 200 and r.json()["estado"] == "completado"
    assert entorno.stock() == STOCK - 1
    # el endpoint de siempre también sirve para la compra offline (mismo resultado que verificar/APROBAR)
    assert entorno.http.patch(f"/pagos/{offline}/confirmar-qr", json={"aprobar": True}).status_code == 200
    assert entorno.stock() == STOCK - 1 - 2


# ---------------------------------------------------------------------------------------------------------------
# POST /pagos/{id}/verificar
# ---------------------------------------------------------------------------------------------------------------

def test_aprobar_descuenta_el_stock_y_completa_la_venta(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()
    assert entorno.stock() == STOCK

    r = entorno.verificar(pago_id, "APROBAR", "encargado")

    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert (cuerpo["estado"], cuerpo["venta_estado"], cuerpo["reembolso_id"]) == ("completado", "completada", None)
    assert cuerpo["confirmado_por_id"] == entorno.ids["encargado"] and cuerpo["confirmado_en"] is not None
    assert entorno.obtener(Venta, id=venta_id).estado == "completada"
    assert entorno.stock() == STOCK - 2, "ahora sí baja el stock real"
    with entorno.Sesion() as db:
        (mov,) = db.query(MovimientoInventario).all()
        assert (mov.tipo, mov.cantidad) == ("venta", 2)
    assert entorno.pendientes("cajero").json() == []
    assert entorno.contar(Reembolso) == 0
    assert entorno.verificar(pago_id, "APROBAR").status_code == 409  # ya procesado: no se descuenta dos veces
    assert entorno.stock() == STOCK - 2


def test_aprobar_sin_stock_cancela_la_venta_y_deja_el_reembolso_pendiente(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()
    entorno.poner_stock(1)  # mientras tanto se vendió: ya no alcanza para 2

    r = entorno.verificar(pago_id, "APROBAR")

    assert r.status_code == 409
    assert "reembolso" in r.json()["detail"]
    assert entorno.obtener(Venta, id=venta_id).estado == "cancelada"
    pago = entorno.pago_de(venta_id)
    assert pago.estado == "fallido" and "FALLO STOCK" in pago.referencia_externa
    assert entorno.stock() == 1, "no se vendió nada"
    reembolso = entorno.obtener(Reembolso, venta_id=venta_id)
    assert (reembolso.estado, float(reembolso.monto), reembolso.cliente_id) == ("pendiente", 200.0, entorno.ids["cliente"])


def test_rechazar_cancela_la_venta_no_toca_el_stock_y_crea_el_reembolso_pendiente(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()

    r = entorno.verificar(pago_id, "RECHAZAR", "cajero", motivo="el monto no coincide")

    assert r.status_code == 200, r.text
    cuerpo = r.json()
    assert (cuerpo["estado"], cuerpo["venta_estado"]) == ("fallido", "cancelada")
    assert cuerpo["referencia_externa"] == "RECHAZADO: el monto no coincide"
    assert entorno.obtener(Venta, id=venta_id).estado == "cancelada"
    assert entorno.stock() == STOCK, "nunca se había descontado: no hay nada que devolver"
    reembolso = entorno.obtener(Reembolso, venta_id=venta_id)
    assert cuerpo["reembolso_id"] == reembolso.id
    assert (reembolso.estado, float(reembolso.monto), reembolso.cliente_id) == ("pendiente", 200.0, entorno.ids["cliente"])
    assert entorno.pendientes("cajero").json() == []
    assert entorno.verificar(pago_id, "RECHAZAR").status_code == 409  # ya procesado


def test_tras_rechazar_el_cliente_sube_su_qr_y_el_personal_completa_el_reembolso(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()
    reembolso_id = entorno.verificar(pago_id, "RECHAZAR").json()["reembolso_id"]

    entorno.como("cliente")
    mios = entorno.http.get("/devoluciones/mis-reembolsos").json()
    assert [(r["id"], r["venta_id"], r["estado"]) for r in mios] == [(reembolso_id, venta_id, "pendiente")]
    subida = entorno.http.post(f"/devoluciones/{reembolso_id}/qr", files={"archivo": ("qr.png", PNG, "image/png")})
    assert subida.status_code == 200 and subida.json()["tiene_qr"] is True

    entorno.como("cajero")
    (pendiente,) = entorno.http.get("/devoluciones/reembolsos", params={"estado": "pendiente"}).json()
    assert pendiente["venta_id"] == venta_id and pendiente["qr_devolucion_url"]
    hecho = entorno.http.post("/devoluciones/reembolsos/procesar", json={"venta_id": venta_id})
    assert hecho.status_code == 200 and hecho.json()["estado"] == "reembolsado"
    assert entorno.obtener(Venta, id=venta_id).estado == "reembolsada"


def test_verificar_respeta_permisos_empresa_y_sucursal(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()

    assert entorno.verificar(pago_id, "APROBAR", "cliente").status_code == 403
    assert entorno.verificar(pago_id, "APROBAR", "admin_ajeno").status_code == 404  # otra empresa
    assert entorno.verificar(pago_id, "APROBAR", "cajero_b").status_code == 403  # otra sucursal
    assert entorno.verificar(999999, "APROBAR").status_code == 404
    assert entorno.obtener(Venta, id=venta_id).estado == "pendiente" and entorno.stock() == STOCK
    assert entorno.verificar(pago_id, "APROBAR", "admin").status_code == 200  # el administrador de la empresa sí


def test_verificar_solo_acepta_pagos_qr_con_comprobante_y_una_accion_valida(entorno):
    venta_id, pago_id = entorno.comprar_y_obtener()
    assert entorno.verificar(pago_id, "BORRAR").status_code == 422

    with entorno.Sesion() as db:
        efectivo = Pago(venta_id=venta_id, metodo="efectivo", monto=200, estado="pendiente")
        sin_comprobante = Pago(venta_id=venta_id, metodo="qr", monto=200, estado="pendiente")
        db.add_all([efectivo, sin_comprobante])
        db.commit()
        efectivo_id, sin_id = efectivo.id, sin_comprobante.id
    assert entorno.verificar(efectivo_id, "APROBAR").status_code == 400
    assert entorno.verificar(sin_id, "APROBAR").status_code == 400


def test_mis_compras_trae_el_reembolso_de_la_compra_rechazada_con_el_estado_de_su_qr(entorno):
    """El móvil (Mis Compras) se entera por aquí de que debe pedir el QR y de si el servidor ya lo recibió."""
    venta_id, pago_id = entorno.comprar_y_obtener()

    entorno.como("cliente")
    (pendiente,) = entorno.http.get("/ventas/mis-compras").json()
    assert (pendiente["id"], pendiente["estado"], pendiente["reembolso"]) == (venta_id, "pendiente", None)

    reembolso_id = entorno.verificar(pago_id, "RECHAZAR").json()["reembolso_id"]
    entorno.como("cliente")
    (rechazada,) = entorno.http.get("/ventas/mis-compras").json()
    assert rechazada["estado"] == "cancelada"
    assert (rechazada["reembolso"]["id"], rechazada["reembolso"]["estado"]) == (reembolso_id, "pendiente")
    assert (rechazada["reembolso"]["monto"], rechazada["reembolso"]["tiene_qr"], rechazada["reembolso"]["qr_devolucion_url"]) == (200.0, False, None)

    entorno.http.post(f"/devoluciones/{reembolso_id}/qr", files={"archivo": ("qr.png", PNG, "image/png")})
    (con_qr,) = entorno.http.get("/ventas/mis-compras").json()
    assert con_qr["reembolso"]["tiene_qr"] is True and con_qr["reembolso"]["qr_devolucion_url"]

    entorno.como("cajero")
    assert entorno.http.post("/devoluciones/reembolsos/procesar", json={"venta_id": venta_id}).status_code == 200
    entorno.como("cliente")
    (hecha,) = entorno.http.get("/ventas/mis-compras").json()
    assert (hecha["estado"], hecha["reembolso"]["estado"]) == ("reembolsada", "reembolsado")
