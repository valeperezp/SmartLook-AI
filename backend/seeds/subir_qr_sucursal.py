"""Sube (o vuelve a subir) el QR bancario de una sucursal a un backend desplegado, p. ej. Render.

¿Para qué sirve? El QR se guarda como archivo en `uploads/qr/` del servidor que recibe la subida, y la fila que lo apunta vive en la
base (compartida). En Render ese disco NO es persistente: cada reinicio o deploy borra los archivos subidos aunque la fila siga en la
base. El síntoma: `GET /sucursales/1/qr` responde 200 con una `imagen_url`, pero esa imagen da 404 y la app móvil no puede guardar el
QR para cobrar compras sin conexión. Este script lo vuelve a subir directamente a ese servidor (login + `POST /sucursales/{id}/qr`) y
comprueba que la imagen ya se descarga.

Uso (desde la carpeta backend; solo hace falta `httpx`, que ya está en las dependencias):
    python -m seeds.subir_qr_sucursal --email encargado@tienda.bo --password "..." --sucursal 1
    python -m seeds.subir_qr_sucursal --email admin@tienda.bo --password "..." --todas   # TODAS las sucursales de la empresa
    python -m seeds.subir_qr_sucursal --simular            # solo revisa la imagen: no toca el servidor ni pide credenciales
    python -m seeds.subir_qr_sucursal --todas --simular    # solo LEE: dice a qué sucursales les subiría el QR

Qué se necesita:
- Un usuario encargado de esa sucursal, o un administrador de la empresa. Con `--todas` hace falta un ADMINISTRADOR: un encargado
  solo puede subir a su propia sucursal (las demás darían 403). Las credenciales también pueden ir en las variables
  SMARTLOOK_EMAIL / SMARTLOOK_PASSWORD (el servidor por defecto, en SMARTLOOK_API).
- Una imagen PNG/JPG/WEBP. Sin `--imagen` usa `seeds/qr_prueba_centro.png`, un QR de PRUEBA (no es el de tu banco: para cobrar de
  verdad sube el QR real de la sucursal, también desde la web: Encargado → Mi QR).

Con `--todas` NO se reemplaza el QR de una sucursal que ya tiene uno activo cuya imagen se descarga (podría ser el real): solo se sube
a las que no tienen QR o cuya imagen ya no existe. `--forzar` lo reemplaza igual.

OJO: sube a ese servidor y reemplaza el QR activo de la sucursal. En Render el archivo vuelve a perderse en el próximo reinicio o
deploy; para que dure hace falta un disco persistente o guardar el QR en un almacenamiento externo (como las fotos de productos).
"""
import argparse
import os
import sys

import httpx

API_POR_DEFECTO = "https://smartlook-ai-api.onrender.com"
IMAGEN_POR_DEFECTO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "qr_prueba_centro.png")
MAX_BYTES = 10 * 1024 * 1024
TIPOS = {"png": "image/png", "jpg": "image/jpeg", "webp": "image/webp"}
TIEMPO_MAXIMO = 120  # Render gratuito tarda en despertar


class ErrorQr(Exception):
    """Algo impidió subir el QR (el mensaje dice qué)."""


def detectar_tipo(contenido: bytes) -> str:
    """png | jpg | webp según los primeros bytes del archivo (no la extensión)."""
    if contenido.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if contenido.startswith(b"\xff\xd8\xff"):
        return "jpg"
    if contenido[:4] == b"RIFF" and contenido[8:12] == b"WEBP":
        return "webp"
    raise ErrorQr("El archivo no es una imagen PNG, JPG o WEBP válida")


def leer_imagen(ruta: str) -> tuple[bytes, str]:
    try:
        with open(ruta, "rb") as f:
            contenido = f.read()
    except OSError as e:
        raise ErrorQr(f"No se pudo leer la imagen '{ruta}': {e.strerror or e}")
    if not contenido:
        raise ErrorQr("La imagen está vacía")
    if len(contenido) > MAX_BYTES:
        raise ErrorQr(f"La imagen supera los {MAX_BYTES // (1024 * 1024)} MB")
    return contenido, detectar_tipo(contenido)


def _detalle(r: httpx.Response) -> str:
    try:
        return str(r.json().get("detail", r.text))[:200]
    except Exception:
        return r.text[:200]


def iniciar_sesion(cliente: httpx.Client, api: str, email: str, password: str) -> str:
    r = cliente.post(f"{api}/auth/login", json={"email": email, "password": password})
    if r.status_code != 200:
        raise ErrorQr(f"No se pudo iniciar sesión ({r.status_code}): {_detalle(r)}")
    token = r.json().get("access_token")
    if not token:
        raise ErrorQr("El servidor no devolvió un token de sesión")
    return token


def subir_qr(cliente: httpx.Client, api: str, token: str, sucursal_id: int, contenido: bytes, extension: str) -> dict:
    r = cliente.post(
        f"{api}/sucursales/{sucursal_id}/qr",
        headers={"Authorization": f"Bearer {token}"},
        files={"archivo": (f"qr_sucursal_{sucursal_id}.{extension}", contenido, TIPOS[extension])},
    )
    if r.status_code not in (200, 201):
        raise ErrorQr(f"El servidor rechazó el QR ({r.status_code}): {_detalle(r)}")
    return r.json()


def imagen_disponible(cliente: httpx.Client, qr: dict) -> bool:
    """¿La imagen que el servidor dice tener se puede descargar de verdad? (es lo que hace la app móvil)."""
    try:
        r = cliente.get(qr["imagen_url"])
    except httpx.HTTPError:
        return False
    return r.status_code == 200 and len(r.content) > 0


def _auth(token: str | None) -> dict:
    return {"Authorization": f"Bearer {token}"} if token else {}


def listar_sucursales(cliente: httpx.Client, api: str, token: str | None = None) -> list[dict]:
    """Las sucursales de la empresa (con sesión, la del usuario; sin sesión, la tienda por defecto)."""
    r = cliente.get(f"{api}/sucursales", headers=_auth(token))
    if r.status_code != 200:
        raise ErrorQr(f"No se pudo listar las sucursales ({r.status_code}): {_detalle(r)}")
    return r.json()


def qr_vigente_funciona(cliente: httpx.Client, api: str, sucursal_id: int, token: str | None = None) -> bool:
    """¿La sucursal tiene un QR activo cuya imagen se descarga de verdad? (lo que necesita la app móvil)."""
    r = cliente.get(f"{api}/sucursales/{sucursal_id}/qr", headers=_auth(token))
    return r.status_code == 200 and imagen_disponible(cliente, r.json())


def subir_todas(api: str, email: str | None, password: str | None, ruta_imagen: str, *, simular: bool = False, forzar: bool = False,
                cliente: httpx.Client | None = None) -> list[dict]:
    """Sube el QR a TODAS las sucursales de la empresa. Devuelve una fila por sucursal: omitida | subida | se_subiria | error.

    Un fallo en una sucursal (p. ej. un encargado sin permiso sobre ella) no detiene a las demás. Con `simular` solo LEE (no inicia
    sesión ni sube nada) y dice a cuáles se les subiría.
    """
    contenido, extension = leer_imagen(ruta_imagen)
    if not simular and (not email or not password):
        raise ErrorQr("Faltan el correo y la contraseña (--email / --password o SMARTLOOK_EMAIL / SMARTLOOK_PASSWORD)")

    propio = cliente is None
    cliente = cliente or httpx.Client(timeout=TIEMPO_MAXIMO)
    resultados: list[dict] = []
    try:
        token = None if simular else iniciar_sesion(cliente, api, email, password)
        for sucursal in listar_sucursales(cliente, api, token):
            fila = {"sucursal": sucursal["id"], "nombre": sucursal.get("nombre", "")}
            try:
                if not forzar and qr_vigente_funciona(cliente, api, sucursal["id"], token):
                    fila["resultado"] = "omitida"  # ya tiene un QR que se descarga: no se reemplaza
                elif simular:
                    fila["resultado"] = "se_subiria"
                else:
                    qr = subir_qr(cliente, api, token, sucursal["id"], contenido, extension)
                    fila.update(resultado="subida", qr_id=qr.get("id"), imagen_url=qr.get("imagen_url"), verificada=imagen_disponible(cliente, qr))
            except ErrorQr as e:
                fila.update(resultado="error", detalle=str(e))
            except httpx.HTTPError as e:
                fila.update(resultado="error", detalle=f"No se pudo hablar con el servidor: {e}")
            resultados.append(fila)
    except httpx.HTTPError as e:
        raise ErrorQr(f"No se pudo hablar con el servidor: {e}")
    finally:
        if propio:
            cliente.close()
    return resultados


def subir(api: str, email: str | None, password: str | None, sucursal_id: int, ruta_imagen: str, *, simular: bool = False,
          cliente: httpx.Client | None = None) -> dict:
    """Valida la imagen, inicia sesión, sube el QR y comprueba que se descarga. Devuelve un resumen."""
    contenido, extension = leer_imagen(ruta_imagen)
    resumen = {"api": api, "sucursal": sucursal_id, "imagen": ruta_imagen, "tipo": extension, "bytes": len(contenido), "simulado": simular}
    if simular:
        return resumen
    if not email or not password:
        raise ErrorQr("Faltan el correo y la contraseña (--email / --password o SMARTLOOK_EMAIL / SMARTLOOK_PASSWORD)")

    propio = cliente is None
    cliente = cliente or httpx.Client(timeout=TIEMPO_MAXIMO)
    try:
        token = iniciar_sesion(cliente, api, email, password)
        qr = subir_qr(cliente, api, token, sucursal_id, contenido, extension)
        resumen.update({"qr_id": qr.get("id"), "imagen_url": qr.get("imagen_url"), "verificada": imagen_disponible(cliente, qr)})
    except httpx.HTTPError as e:
        raise ErrorQr(f"No se pudo hablar con el servidor: {e}")
    finally:
        if propio:
            cliente.close()
    return resumen


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Sube el QR bancario de una sucursal a un backend desplegado.")
    p.add_argument("--api", default=os.environ.get("SMARTLOOK_API", API_POR_DEFECTO), help=f"URL del backend (por defecto {API_POR_DEFECTO})")
    p.add_argument("--email", default=os.environ.get("SMARTLOOK_EMAIL"), help="correo de un encargado de la sucursal o de un administrador")
    p.add_argument("--password", default=os.environ.get("SMARTLOOK_PASSWORD"))
    p.add_argument("--sucursal", type=int, default=1, help="id de la sucursal (1 = Sucursal Centro)")
    p.add_argument("--todas", action="store_true", help="subir el QR a TODAS las sucursales de la empresa (requiere un administrador)")
    p.add_argument("--forzar", action="store_true", help="con --todas: reemplazar también el QR de las sucursales que ya tienen uno que funciona")
    p.add_argument("--imagen", default=IMAGEN_POR_DEFECTO, help="imagen del QR (por defecto un QR de prueba)")
    p.add_argument("--simular", action="store_true", help="solo revisa la imagen; no toca el servidor")
    a = p.parse_args(argv)

    if a.todas:
        return _main_todas(a)

    try:
        r = subir(a.api.rstrip("/"), a.email, a.password, a.sucursal, a.imagen, simular=a.simular)
    except ErrorQr as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if r["simulado"]:
        print(f"SIMULACIÓN: la imagen {r['imagen']} es un {r['tipo'].upper()} válido de {r['bytes']} bytes; se subiría a {r['api']} (sucursal {r['sucursal']}).")
        return 0
    print(f"QR subido a la sucursal {r['sucursal']} (id {r['qr_id']}): {r['imagen_url']}")
    if r["verificada"]:
        print("OK: la imagen ya se puede descargar. Actualiza el catálogo en la app (con internet) para que la guarde en el celular.")
        return 0
    print("AVISO: el servidor aceptó el QR pero la imagen todavía no se descarga (¿se reinició el servidor?). Vuelve a ejecutar el script.", file=sys.stderr)
    return 2


ETIQUETAS = {
    "omitida": "ya tenía un QR que funciona (no se reemplazó)",
    "se_subiria": "se le subiría el QR",
    "subida": "QR subido",
    "error": "ERROR",
}


def _main_todas(a: argparse.Namespace) -> int:
    try:
        filas = subir_todas(a.api.rstrip("/"), a.email, a.password, a.imagen, simular=a.simular, forzar=a.forzar)
    except ErrorQr as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    for f in filas:
        extra = ""
        if f["resultado"] == "subida":
            extra = f" (id {f['qr_id']}) → imagen {'disponible' if f['verificada'] else 'AÚN NO DISPONIBLE'}: {f['imagen_url']}"
        elif f["resultado"] == "error":
            extra = f": {f['detalle']}"
        print(f"  Sucursal {f['sucursal']} ({f['nombre']}): {ETIQUETAS[f['resultado']]}{extra}")
    mal = [f for f in filas if f["resultado"] == "error" or (f["resultado"] == "subida" and not f["verificada"])]
    print(f"{len(filas)} sucursal(es): {len(filas) - len(mal)} bien, {len(mal)} con problemas." + (" (SIMULACIÓN: no se subió nada)" if a.simular else ""))
    return 2 if mal else 0


if __name__ == "__main__":
    sys.exit(main())
