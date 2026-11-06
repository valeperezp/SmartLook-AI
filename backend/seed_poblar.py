"""Puebla la tienda 'smartlook' vía API (respeta las reglas del negocio): actividad en todos los estados,
una transferencia y el entrenamiento de ML. Requiere las cuentas de seed_usuarios.py. Ejecutar UNA vez.

Dentro del contenedor del backend:
    docker compose cp backend/seed_poblar.py backend:/app/seed_poblar.py
    docker compose exec -w /app -e BASE_URL=http://localhost:8000 backend python seed_poblar.py
"""
import json
import os
import urllib.error
import urllib.request
import uuid

BASE = os.environ.get("BASE_URL", "http://localhost:8001")
PASS = "Demo1234!"
EMP = "smartlook"
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63f8cfc0f01f0005000201a52f6ad60000000049454e44ae426082")
creados = {"ventas": 0, "reservas": 0, "pagos": 0, "movimientos": 0, "transferencias": 0}


def llamar(metodo, ruta, tok=None, datos=None, archivo=None):
    h = {}
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    cuerpo = None
    if archivo:
        lim = uuid.uuid4().hex
        n, c, t = archivo
        cuerpo = (f'--{lim}\r\nContent-Disposition: form-data; name="archivo"; filename="{n}"\r\nContent-Type: {t}\r\n\r\n').encode() + c + f"\r\n--{lim}--\r\n".encode()
        h["Content-Type"] = f"multipart/form-data; boundary={lim}"
    elif datos is not None:
        cuerpo = json.dumps(datos).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE + ruta, data=cuerpo, method=metodo, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            c = r.read().decode()
            return r.status, (json.loads(c) if c else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try:
            return e.code, json.loads(t)
        except Exception:
            return e.code, t


def login(email):
    st, r = llamar("POST", "/auth/login", datos={"email": email, "password": PASS, "empresa": EMP})
    assert st == 200, (email, st, r)
    return r["access_token"]


def paso(msg, st, r=None, cuenta=None):
    ok = st in (200, 201)
    print(("  OK    " if ok else "  FALLO ") + msg + ("" if ok else f" -> {st} {str(r)[:140]}"))
    if ok and cuenta:
        creados[cuenta] += 1
    return ok


admin, enc, caj, cli = (login(e) for e in ("admin@smartlook.bo", "encargado.centro@smartlook.bo", "cajero.centro@smartlook.bo", "cliente@smartlook.bo"))

print("== Inventario de Sucursal Centro")
st, inv = llamar("GET", "/inventario/mi-sucursal", enc)
suc = inv[0]["sucursal_id"]
disp = [i for i in inv if i["cantidad_disponible"] >= 8 and i.get("talla_id") and i.get("color_id")]
assert len(disp) >= 6, f"pocas variantes con stock ({len(disp)})"
paso("salida total -> agotado", *llamar("POST", "/inventario/movimientos", enc, {"inventario_id": disp[0]["id"], "tipo": "salida", "cantidad": disp[0]["cantidad_disponible"], "motivo": "Venta mayorista (demo)"}), cuenta="movimientos")
paso("salida parcial -> stock bajo", *llamar("POST", "/inventario/movimientos", enc, {"inventario_id": disp[1]["id"], "tipo": "salida", "cantidad": disp[1]["cantidad_disponible"] - 2, "motivo": "Venta de temporada (demo)"}), cuenta="movimientos")
for i in disp[2:4]:
    paso("entrada de 10 unidades", *llamar("POST", "/inventario/movimientos", enc, {"inventario_id": i["id"], "tipo": "entrada", "cantidad": 10, "motivo": "Reposición semanal (demo)"}), cuenta="movimientos")
libres = disp[2:]


def linea(i, n=1):
    return {"producto_id": i["producto_id"], "talla_id": i["talla_id"], "color_id": i["color_id"], "cantidad": n}


def orden(i, n=1):
    st, v = llamar("POST", "/ventas/online", cli, {"sucursal_id": suc, "items": [linea(i, n)]})
    assert st == 201, (st, v)
    creados["ventas"] += 1
    return v


def qr(v):
    st, p = llamar("POST", "/pagos/qr", cli, {"venta_id": v["id"]})
    assert st in (200, 201), (st, p)
    creados["pagos"] += 1
    llamar("POST", f"/pagos/{p['id']}/comprobante", cli, archivo=("comprobante.png", PNG, "image/png"))
    return p


print("== Pagos en todos los estados")
p = qr(orden(libres[0], 2))
paso("pago QR aprobado", *llamar("PATCH", f"/pagos/{p['id']}/confirmar-qr", caj, {"aprobar": True}))
p = qr(orden(libres[1]))
paso("pago QR rechazado", *llamar("PATCH", f"/pagos/{p['id']}/confirmar-qr", caj, {"aprobar": False, "motivo_rechazo": "El monto no coincide (demo)"}))
for k in range(2):
    qr(orden(libres[k + 2]))
    print("  OK    pago QR pendiente de verificación")
v = orden(libres[0])
paso("pago en efectivo pendiente", *llamar("POST", "/pagos/efectivo", cli, {"venta_id": v["id"]}), cuenta="pagos")

print("== Venta presencial del cajero")
paso("venta de caja completada", *llamar("POST", "/ventas", caj, {"sucursal_id": suc, "items": [linea(libres[1], 2)]}), cuenta="ventas")

print("== Reservas en cada estado")


def reserva(i):
    st, r = llamar("POST", "/reservas", cli, {"sucursal_id": suc, "items": [linea(i)]})
    assert st in (200, 201), (st, r)
    creados["reservas"] += 1
    return r["id"]


a, b, c = reserva(libres[0]), reserva(libres[1]), reserva(libres[2])
reserva(libres[3])
for rid in (a, b):
    llamar("PATCH", f"/reservas/{rid}/estado?nuevo_estado=confirmada", enc)
llamar("PATCH", f"/reservas/{b}/estado?nuevo_estado=atendida", enc)
llamar("PATCH", f"/reservas/{c}/cancelar", cli)
print("  OK    4 reservas: pendiente, confirmada, atendida, cancelada")

print("== Transferencia Centro -> otra sucursal")
st, sucs = llamar("GET", "/sucursales", admin)
dest = next(s["id"] for s in sucs if s["id"] != suc)
st, t = llamar("POST", "/transferencias", admin, {"sucursal_origen_id": suc, "sucursal_destino_id": dest, "motivo": "Reposición para fin de semana (demo)", "items": [{"inventario_id": libres[0]["id"], "cantidad": 2}]})
if paso("transferencia solicitada", st, t, cuenta="transferencias"):
    paso("transferencia enviada", *llamar("POST", f"/transferencias/{t['id']}/enviar", admin))
    paso("transferencia recibida", *llamar("POST", f"/transferencias/{t['id']}/recibir", admin))

print("== Machine Learning")
paso("modelos de ML entrenados", *llamar("POST", "/analitica/entrenar", admin))
print("CREADOS:", creados)
print("HECHO")
