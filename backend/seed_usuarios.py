"""Crea cuentas demo en la tienda 'smartlook' (empresa_id=1). Idempotente: no toca las cuentas existentes.

Ejecutar dentro del contenedor del backend:
    docker compose cp backend/seed_usuarios.py backend:/app/seed_usuarios.py
    docker compose exec -w /app -e PYTHONPATH=/app backend python seed_usuarios.py

Escribe en la base a la que apunte DATABASE_URL (backend/.env). Contraseña demo de todas las cuentas: Demo1234!
"""
from app.modules.usuarios.models import Usuario
from app.shared.db.session import SessionLocal
from app.shared.security import hash_password

PASSWORD_DEMO = "Demo1234!"
EMPRESA_ID = 1  # tienda 'smartlook'
SUCURSAL_CENTRO = 1

CUENTAS = [
    ("admin@smartlook.bo", "Admin SmartLook", "administrador", None),
    ("encargado.centro@smartlook.bo", "Encargado Centro", "encargado_sucursal", SUCURSAL_CENTRO),
    ("cajero.centro@smartlook.bo", "Cajero Centro", "cajero", SUCURSAL_CENTRO),
    ("cliente@smartlook.bo", "Cliente Demo", "cliente", None),
]

db = SessionLocal()
try:
    hash_demo = hash_password(PASSWORD_DEMO)
    creadas = 0
    for email, nombre, rol, sucursal_id in CUENTAS:
        if db.query(Usuario).filter_by(email=email).first():
            print(f"[=] ya existe   {rol:<20} {email}")
            continue
        db.add(Usuario(email=email, nombre=nombre, password_hash=hash_demo, rol=rol,
                       empresa_id=EMPRESA_ID, sucursal_id=sucursal_id))
        creadas += 1
        print(f"[+] creado      {rol:<20} {email}")
    db.commit()
    print(f"USUARIOS_CREADOS={creadas}")
finally:
    db.close()
