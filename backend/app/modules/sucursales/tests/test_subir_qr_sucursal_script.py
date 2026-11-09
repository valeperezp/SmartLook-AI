"""El script `seeds/subir_qr_sucursal.py` (re-subir el QR de una sucursal a un backend desplegado).

Usa un servidor FALSO (httpx.MockTransport): no sale a la red ni toca ninguna base. Ejecutar desde `backend/`:  python -m pytest app/modules -v
"""
import re

import httpx
import pytest

from seeds import subir_qr_sucursal as script

_Client = httpx.Client  # el real (algunos tests reemplazan httpx.Client para el programa principal)

API = "https://api.falsa.test"
URL_IMAGEN = f"{API}/uploads/qr/sucursal_1_nuevo.png"


class ServidorFalso:
    """Un backend de mentira: login, subida del QR y descarga de la imagen. Anota todo lo que le piden."""

    def __init__(self, *, login=200, subida=201, imagen=200):
        self.codigos = {"login": login, "subida": subida, "imagen": imagen}
        self.peticiones: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.peticiones.append(request)
        ruta = request.url.path
        if ruta == "/auth/login":
            if self.codigos["login"] != 200:
                return httpx.Response(self.codigos["login"], json={"detail": "Credenciales inválidas"})
            return httpx.Response(200, json={"access_token": "token-falso", "token_type": "bearer"})
        if ruta == "/sucursales/1/qr" and request.method == "POST":
            if self.codigos["subida"] not in (200, 201):
                return httpx.Response(self.codigos["subida"], json={"detail": "Solo podés subir QR de tu sucursal"})
            return httpx.Response(201, json={"id": 14, "sucursal_id": 1, "imagen_path": "qr/sucursal_1_nuevo.png", "activo": True, "imagen_url": URL_IMAGEN})
        if str(request.url) == URL_IMAGEN:
            return httpx.Response(self.codigos["imagen"], content=b"\x89PNG..." if self.codigos["imagen"] == 200 else b'{"detail":"Not Found"}')
        return httpx.Response(404, json={"detail": "Not Found"})

    def cliente(self) -> httpx.Client:
        return httpx.Client(transport=httpx.MockTransport(self))


def subir(servidor: ServidorFalso, **kw):
    args = dict(api=API, email="encargado@t.bo", password="secreta", sucursal_id=1, ruta_imagen=script.IMAGEN_POR_DEFECTO)
    return script.subir(**{**args, **kw}, cliente=servidor.cliente())


def test_la_imagen_de_prueba_que_trae_el_script_es_un_png_valido():
    contenido, extension = script.leer_imagen(script.IMAGEN_POR_DEFECTO)

    assert extension == "png"
    assert contenido.startswith(b"\x89PNG\r\n\x1a\n") and len(contenido) > 500


def test_inicia_sesion_sube_el_qr_a_la_sucursal_y_comprueba_que_la_imagen_ya_se_descarga():
    servidor = ServidorFalso()

    r = subir(servidor)

    assert (r["qr_id"], r["imagen_url"], r["verificada"]) == (14, URL_IMAGEN, True)
    login, subida, descarga = servidor.peticiones
    assert (login.method, login.url.path) == ("POST", "/auth/login")
    assert b'"email"' in login.content and b"encargado@t.bo" in login.content
    assert (subida.method, subida.url.path) == ("POST", "/sucursales/1/qr")
    assert subida.headers["authorization"] == "Bearer token-falso"
    assert subida.headers["content-type"].startswith("multipart/form-data")
    assert b'name="archivo"' in subida.content and b"image/png" in subida.content and b"\x89PNG" in subida.content
    assert str(descarga.url) == URL_IMAGEN  # es lo que hace la app móvil al guardar el QR


def test_avisa_si_el_servidor_acepta_el_qr_pero_la_imagen_sigue_sin_descargarse():
    r = subir(ServidorFalso(imagen=404))

    assert r["verificada"] is False


def test_un_login_o_una_subida_rechazados_explican_el_motivo():
    with pytest.raises(script.ErrorQr, match=r"iniciar sesión \(401\).*Credenciales inválidas"):
        subir(ServidorFalso(login=401))
    with pytest.raises(script.ErrorQr, match=r"rechazó el QR \(403\).*tu sucursal"):
        subir(ServidorFalso(subida=403))


def test_faltan_credenciales():
    servidor = ServidorFalso()

    with pytest.raises(script.ErrorQr, match="Faltan el correo y la contraseña"):
        subir(servidor, email=None)
    assert servidor.peticiones == []


def test_una_imagen_que_no_sirve_se_rechaza_antes_de_tocar_el_servidor(tmp_path):
    servidor = ServidorFalso()
    texto = tmp_path / "qr.png"
    texto.write_bytes(b"esto no es una imagen aunque diga .png")
    vacia = tmp_path / "vacia.png"
    vacia.write_bytes(b"")

    with pytest.raises(script.ErrorQr, match="no es una imagen"):
        subir(servidor, ruta_imagen=str(texto))
    with pytest.raises(script.ErrorQr, match="vacía"):
        subir(servidor, ruta_imagen=str(vacia))
    with pytest.raises(script.ErrorQr, match="No se pudo leer"):
        subir(servidor, ruta_imagen=str(tmp_path / "no_existe.png"))
    assert servidor.peticiones == []


def test_acepta_jpg_y_webp_segun_su_contenido(tmp_path):
    for nombre, contenido, tipo in [("a.bin", b"\xff\xd8\xff\xe0" + b"0" * 20, "jpg"), ("b.bin", b"RIFF\x00\x00\x00\x00WEBP" + b"0" * 20, "webp")]:
        ruta = tmp_path / nombre
        ruta.write_bytes(contenido)
        assert script.leer_imagen(str(ruta)) == (contenido, tipo)


def test_simular_solo_revisa_la_imagen_y_no_toca_el_servidor():
    servidor = ServidorFalso()

    r = subir(servidor, simular=True, email=None, password=None)

    assert r["simulado"] is True and r["tipo"] == "png" and r["bytes"] > 0
    assert servidor.peticiones == []


def test_el_programa_principal_devuelve_el_codigo_de_salida_correcto(capsys, monkeypatch):
    monkeypatch.delenv("SMARTLOOK_EMAIL", raising=False)
    monkeypatch.delenv("SMARTLOOK_PASSWORD", raising=False)

    assert script.main(["--simular"]) == 0
    assert "SIMULACIÓN" in capsys.readouterr().out
    assert script.main([]) == 1  # sin credenciales
    assert "Faltan el correo" in capsys.readouterr().err
    assert script.main(["--simular", "--imagen", "no_existe.png"]) == 1


# ---------------------------------------------------------------------------------------------------------------
# --todas: el QR a TODAS las sucursales de la empresa
# ---------------------------------------------------------------------------------------------------------------

class ServidorEmpresa:
    """Un backend de mentira con 3 sucursales: la 1 con un QR que funciona, la 2 sin QR y la 3 con la fila del QR pero sin su imagen
    (el caso real de Render). `token` dice quién inicia sesión: "admin" (puede subir a todas) o "encargado" (solo a la sucursal 1)."""

    SUCURSALES = [(1, "Centro"), (2, "Norte"), (3, "Equipetrol")]

    def __init__(self, token="admin"):
        self.token = token
        self.qr = {1: {"id": 10, "ok": True}, 3: {"id": 30, "ok": False}}
        self.peticiones: list[httpx.Request] = []
        self._siguiente = 100

    def _json(self, sucursal_id: int) -> dict:
        qr = self.qr[sucursal_id]
        return {"id": qr["id"], "sucursal_id": sucursal_id, "activo": True, "imagen_url": f"{API}/uploads/qr/s{sucursal_id}_{qr['id']}.png"}

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.peticiones.append(request)
        ruta = request.url.path
        if ruta == "/auth/login":
            return httpx.Response(200, json={"access_token": self.token, "token_type": "bearer"})
        if ruta == "/sucursales":
            return httpx.Response(200, json=[{"id": i, "nombre": n, "activa": True} for i, n in self.SUCURSALES])
        qr = re.fullmatch(r"/sucursales/(\d+)/qr", ruta)
        if qr:
            sucursal_id = int(qr.group(1))
            if request.method == "POST":
                if request.headers.get("authorization") != f"Bearer {self.token}":
                    return httpx.Response(401, json={"detail": "No autenticado"})
                if self.token == "encargado" and sucursal_id != 1:
                    return httpx.Response(403, json={"detail": "Solo podés subir QR de tu sucursal"})
                self._siguiente += 1
                self.qr[sucursal_id] = {"id": self._siguiente, "ok": True}
                return httpx.Response(201, json=self._json(sucursal_id))
            if sucursal_id in self.qr:
                return httpx.Response(200, json=self._json(sucursal_id))
            return httpx.Response(404, json={"detail": "La sucursal no tiene QR configurado"})
        imagen = re.fullmatch(r"/uploads/qr/s(\d+)_(\d+)\.png", ruta)
        if imagen:
            fila = self.qr.get(int(imagen.group(1)))
            if fila and fila["id"] == int(imagen.group(2)) and fila["ok"]:
                return httpx.Response(200, content=b"\x89PNG...")
        return httpx.Response(404, json={"detail": "Not Found"})

    def cliente(self) -> httpx.Client:
        return _Client(transport=httpx.MockTransport(self))

    def subidas(self) -> list[int]:
        return [int(re.search(r"/sucursales/(\d+)/qr", str(p.url)).group(1)) for p in self.peticiones if p.method == "POST" and p.url.path.endswith("/qr")]

    def logins(self) -> int:
        return sum(1 for p in self.peticiones if p.url.path == "/auth/login")


def subir_todas(servidor: ServidorEmpresa, **kw) -> dict[int, dict]:
    args = dict(api=API, email="admin@t.bo", password="secreta", ruta_imagen=script.IMAGEN_POR_DEFECTO)
    filas = script.subir_todas(**{**args, **kw}, cliente=servidor.cliente())
    return {f["sucursal"]: f for f in filas}


def test_todas_sube_el_qr_solo_a_las_sucursales_que_no_tienen_uno_que_funcione():
    servidor = ServidorEmpresa()

    filas = subir_todas(servidor)

    assert {i: f["resultado"] for i, f in filas.items()} == {1: "omitida", 2: "subida", 3: "subida"}
    assert filas[2]["verificada"] is True and filas[3]["verificada"] is True  # la imagen ya se descarga (la 3 tenía la fila sin archivo)
    assert servidor.subidas() == [2, 3], "la 1 ya tenía un QR que funciona: no se reemplaza"
    assert servidor.logins() == 1, "se inicia sesión una sola vez"
    assert all(p.headers["authorization"] == "Bearer admin" for p in servidor.peticiones if p.method == "POST" and p.url.path.endswith("/qr"))


def test_todas_con_forzar_reemplaza_tambien_la_que_ya_funcionaba():
    servidor = ServidorEmpresa()

    filas = subir_todas(servidor, forzar=True)

    assert {f["resultado"] for f in filas.values()} == {"subida"}
    assert servidor.subidas() == [1, 2, 3]


def test_todas_un_fallo_en_una_sucursal_no_detiene_a_las_demas():
    servidor = ServidorEmpresa(token="encargado")  # solo puede subir a la sucursal 1

    filas = subir_todas(servidor, forzar=True)

    assert filas[1]["resultado"] == "subida"
    for sucursal in (2, 3):
        assert filas[sucursal]["resultado"] == "error" and "403" in filas[sucursal]["detalle"] and "tu sucursal" in filas[sucursal]["detalle"]
    assert servidor.subidas() == [1, 2, 3], "se intentó con todas, sin abortar en la primera que falló"


def test_todas_en_simulacion_solo_lee_y_dice_a_cuales_les_subiria():
    servidor = ServidorEmpresa()

    filas = subir_todas(servidor, simular=True, email=None, password=None)

    assert {i: f["resultado"] for i, f in filas.items()} == {1: "omitida", 2: "se_subiria", 3: "se_subiria"}
    assert servidor.logins() == 0 and servidor.subidas() == []
    assert {p.method for p in servidor.peticiones} == {"GET"}


def test_todas_exige_credenciales_y_una_imagen_valida_antes_de_tocar_el_servidor(tmp_path):
    servidor = ServidorEmpresa()
    invalida = tmp_path / "no_es_imagen.png"
    invalida.write_bytes(b"texto")

    with pytest.raises(script.ErrorQr, match="Faltan el correo y la contraseña"):
        subir_todas(servidor, email=None)
    with pytest.raises(script.ErrorQr, match="no es una imagen"):
        subir_todas(servidor, ruta_imagen=str(invalida))
    assert servidor.peticiones == []


def test_todas_un_login_rechazado_explica_el_motivo():
    class SinPermiso(ServidorEmpresa):
        def __call__(self, request):
            if request.url.path == "/auth/login":
                return httpx.Response(401, json={"detail": "Credenciales inválidas"})
            return super().__call__(request)

    with pytest.raises(script.ErrorQr, match=r"iniciar sesión \(401\).*Credenciales inválidas"):
        script.subir_todas(API, "x@t.bo", "mala", script.IMAGEN_POR_DEFECTO, cliente=_Client(transport=httpx.MockTransport(SinPermiso())))


def test_el_programa_principal_con_todas_imprime_un_resumen_y_devuelve_el_codigo_correcto(capsys, monkeypatch):
    for variable in ("SMARTLOOK_EMAIL", "SMARTLOOK_PASSWORD"):
        monkeypatch.delenv(variable, raising=False)
    servidor = ServidorEmpresa()
    monkeypatch.setattr(httpx, "Client", lambda *a, **k: servidor.cliente())

    assert script.main(["--api", API, "--todas", "--email", "admin@t.bo", "--password", "x"]) == 0
    salida = capsys.readouterr().out
    assert "Sucursal 1 (Centro): ya tenía un QR que funciona" in salida
    assert "Sucursal 2 (Norte): QR subido" in salida and "imagen disponible" in salida
    assert "3 sucursal(es): 3 bien, 0 con problemas." in salida

    solo_encargado = ServidorEmpresa(token="encargado")
    monkeypatch.setattr(httpx, "Client", lambda *a, **k: solo_encargado.cliente())
    assert script.main(["--api", API, "--todas", "--email", "e@t.bo", "--password", "x"]) == 2
    salida = capsys.readouterr().out
    assert "Sucursal 2 (Norte): ERROR" in salida and "1 con problemas" not in salida and "2 con problemas." in salida

    assert script.main(["--api", API, "--todas", "--simular"]) == 0  # sin credenciales: solo lee
    assert "SIMULACIÓN: no se subió nada" in capsys.readouterr().out
    assert script.main(["--api", API, "--todas"]) == 1  # sin credenciales y sin simular
    assert "Faltan el correo" in capsys.readouterr().err
