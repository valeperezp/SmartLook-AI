"""Seed multi-empresa para desarrollo local (CU1–CU4).

Crea planes, el superadmin de la plataforma y tres empresas de ejemplo:
  - smartlook   (plan Profesional, 3 sucursales, catálogo con inventario)
  - urbanstyle  (plan Básico: 1 sucursal → sirve para probar el límite del plan)
  - modaretro   (suscripción vencida → sus usuarios no pueden iniciar sesión)

Es idempotente: se puede correr varias veces sin duplicar datos.

Uso (con los contenedores levantados):
    docker compose exec backend python -m seeds.seed_empresas

Todos los usuarios de prueba usan la contraseña: Demo1234!
"""
import random
import sys

import numpy as np
from datetime import datetime, timedelta

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import app.main  # noqa: F401  registra todos los modelos y crea las tablas
from app.modules.catalogo.models import Categoria, Color, Producto, Talla
from app.modules.empresas.models import Empresa, Plan, Suscripcion
from app.modules.inventario.models import Inventario, MovimientoInventario
from app.modules.proveedores.models import Proveedor
from app.modules.reservas.models import Reserva, ReservaItem
from app.modules.ventas.models import Venta, VentaItem
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.db.session import Base, SessionLocal, engine
from app.shared.security import hash_password

PASSWORD_DEMO = "Demo1234!"

Base.metadata.create_all(bind=engine)
db = SessionLocal()
_hash_demo = hash_password(PASSWORD_DEMO)


def get_or_create(model, defaults=None, **kwargs):
    instance = db.query(model).filter_by(**kwargs).first()
    if instance:
        return instance, False
    instance = model(**kwargs, **(defaults or {}))
    db.add(instance)
    db.flush()
    return instance, True


def usuario(email, nombre, rol, empresa=None, sucursal=None):
    u, creado = get_or_create(
        Usuario,
        email=email,
        defaults={
            "nombre": nombre,
            "password_hash": _hash_demo,
            "rol": rol,
            "empresa_id": empresa.id if empresa else None,
            "sucursal_id": sucursal.id if sucursal else None,
        },
    )
    print(f"  {'[+]' if creado else '[=]'} {rol:<20} {email}")
    return u


def suscribir(empresa, plan, fecha_inicio, fecha_fin=None):
    if db.query(Suscripcion).filter_by(empresa_id=empresa.id).first():
        return
    db.add(Suscripcion(
        empresa_id=empresa.id, plan_id=plan.id, estado="activa",
        fecha_inicio=fecha_inicio, fecha_fin=fecha_fin,
    ))


print("== Planes (CU3)")
planes = {}
# RN-04: Básico hasta 2 sucursales, Profesional hasta 10. RN-05: IA solo en Profesional (y superiores).
for nombre, desc, precio, max_suc, max_usr, max_prod, ia in [
    ("Básico", "Para una tienda que recién empieza", 199, 2, 5, 50, False),
    ("Profesional", "Varias sucursales, reportes con IA y analítica", 499, 10, 20, 500, True),
    ("Empresarial", "Sin límites", 999, None, None, None, True),
]:
    plan, creado = get_or_create(
        Plan, nombre=nombre,
        defaults={"descripcion": desc, "precio_mensual": precio, "max_sucursales": max_suc,
                  "max_usuarios": max_usr, "max_productos": max_prod, "incluye_ia": ia},
    )
    planes[nombre] = plan
    print(f"  {'[+]' if creado else '[=]'} {nombre}")

print("== Superadmin de la plataforma")
usuario("superadmin@smartlook.bo", "Superadmin SmartLook", "superadmin")

# Misma zona que usa el backend para decidir si una suscripción está vigente (no la UTC del contenedor).
hoy = datetime.now(ZONA_HORARIA_LOCAL).date()

print("== Empresa: smartlook (Profesional)")
smartlook, _ = get_or_create(
    Empresa, slug="smartlook",
    defaults={"nombre": "SmartLook Boutique", "nit": "1023456789", "email": "contacto@smartlook.bo",
              "telefono": "+591 3 3456789", "direccion": "Av. Monseñor Rivero 123, Santa Cruz"},
)
suscribir(smartlook, planes["Profesional"], hoy - timedelta(days=30))
suc_centro, _ = get_or_create(Sucursal, nombre="SmartLook Centro", empresa_id=smartlook.id,
                              defaults={"direccion": "Calle 24 de Septiembre 50", "ciudad": "Santa Cruz", "activa": True})
suc_norte, _ = get_or_create(Sucursal, nombre="SmartLook Norte", empresa_id=smartlook.id,
                             defaults={"direccion": "Av. Banzer 4to anillo", "ciudad": "Santa Cruz", "activa": True})
suc_equi, _ = get_or_create(Sucursal, nombre="SmartLook Equipetrol", empresa_id=smartlook.id,
                            defaults={"direccion": "Av. San Martín 300", "ciudad": "Santa Cruz", "activa": True})
usuario("admin@smartlook.bo", "Valeria Admin", "administrador", smartlook)
usuario("encargado.centro@smartlook.bo", "Encargado Centro", "encargado_sucursal", smartlook, suc_centro)
usuario("cajero.centro@smartlook.bo", "Cajero Centro", "cajero", smartlook, suc_centro)
usuario("cliente@smartlook.bo", "Cliente Demo", "cliente", smartlook)

print("== Empresa: urbanstyle (Básico)")
urban, _ = get_or_create(
    Empresa, slug="urbanstyle",
    defaults={"nombre": "Urban Style", "nit": "2034567891", "email": "hola@urbanstyle.bo",
              "telefono": "+591 2 2123456", "direccion": "Calle Sagárnaga 200, La Paz"},
)
suscribir(urban, planes["Básico"], hoy - timedelta(days=10), hoy + timedelta(days=20))
suc_urban, _ = get_or_create(Sucursal, nombre="Urban Style Sagárnaga", empresa_id=urban.id,
                             defaults={"direccion": "Calle Sagárnaga 200", "ciudad": "La Paz", "activa": True})
usuario("admin@urbanstyle.bo", "Admin Urban", "administrador", urban)
usuario("cliente@urbanstyle.bo", "Cliente Urban", "cliente", urban)

print("== Empresa: modaretro (suscripción vencida)")
retro, _ = get_or_create(
    Empresa, slug="modaretro",
    defaults={"nombre": "Moda Retro", "email": "info@modaretro.bo", "direccion": "Cochabamba"},
)
suscribir(retro, planes["Básico"], hoy - timedelta(days=60), hoy - timedelta(days=1))
usuario("admin@modaretro.bo", "Admin Retro", "administrador", retro)

print("== Catálogo maestro (uno por empresa)")


def catalogo_maestro(empresa):
    e = empresa.id
    return {
        "tallas": {n: get_or_create(Talla, nombre=n, empresa_id=e)[0] for n in ["XS", "S", "M", "L", "XL"]},
        "colores": {n: get_or_create(Color, nombre=n, empresa_id=e, defaults={"hex": h})[0]
                    for n, h in [("Negro", "#000000"), ("Blanco", "#FFFFFF"), ("Azul", "#1E40AF"), ("Rojo", "#B91C1C")]},
        "categorias": {n: get_or_create(Categoria, nombre=n, empresa_id=e)[0]
                       for n in ["Camisetas", "Pantalones", "Chaquetas", "Camisas", "Vestidos"]},
    }


maestro = {emp.slug: catalogo_maestro(emp) for emp in (smartlook, urban, retro)}
print("  smartlook, urbanstyle, modaretro: tallas, colores y categorías")

print("== Proveedores")
prov_smartlook, _ = get_or_create(Proveedor, nombre="Textiles Andinos", empresa_id=smartlook.id,
                                  defaults={"contacto": "Rosa Quispe", "email": "ventas@textilesandinos.bo"})
prov_urban, _ = get_or_create(Proveedor, nombre="Street Supply", empresa_id=urban.id,
                              defaults={"contacto": "Marco Rivas", "email": "marco@streetsupply.bo"})
usuario("proveedor@smartlook.bo", "Proveedor Textiles", "proveedor", smartlook)
db.query(Usuario).filter_by(email="proveedor@smartlook.bo").update({"proveedor_id": prov_smartlook.id})

print("== Productos e inventario")
productos_smartlook = [
    ("Camiseta Básica Algodón", "Camiseta de algodón peinado, corte regular.", 89, "Camisetas"),
    ("Camiseta Oversize Gráfica", "Estampado frontal, algodón pesado.", 120, "Camisetas"),
    ("Pantalón Denim Clásico", "Jeans corte recto 100% algodón.", 220, "Pantalones"),
    ("Pantalón Chino Beige", "Pantalón casual para oficina y diario.", 195, "Pantalones"),
    ("Chaqueta Cuero Urbana", "Cuero sintético con cremallera metálica.", 450, "Chaquetas"),
    ("Chaqueta Bomber Negra", "Acolchada ligera para media estación.", 380, "Chaquetas"),
    ("Camisa Lino Manga Larga", "Lino transpirable, regular fit.", 160, "Camisas"),
    ("Camisa Oxford Celeste", "Oxford con cuello abotonado.", 175, "Camisas"),
    ("Vestido Midi Floral", "Estampado floral con lazo a la cintura.", 280, "Vestidos"),
    ("Vestido Gala Elegante", "Vestido largo de noche.", 490, "Vestidos"),
]
productos_urban = [
    ("Hoodie Urban Negro", "Buzo con capucha y bolsillo canguro.", 210, "Chaquetas"),
    ("Jogger Cargo", "Pantalón jogger con bolsillos cargo.", 175, "Pantalones"),
    ("Camiseta Urban Logo", "Camiseta con logo bordado.", 95, "Camisetas"),
]


def cargar_productos(empresa, lista, proveedor):
    categorias = maestro[empresa.slug]["categorias"]
    creados = []
    for nombre, desc, precio, cat in lista:
        p, _ = get_or_create(Producto, nombre=nombre, empresa_id=empresa.id,
                             defaults={"descripcion": desc, "precio": precio, "proveedor_id": proveedor.id,
                                       "categoria_id": categorias[cat].id, "activo": True})
        creados.append(p)
    print(f"  {empresa.slug}: {len(creados)} productos")
    return creados


def stock(producto, sucursal, talla, color, disponible, vendida=0):
    tallas = maestro_por_id[producto.empresa_id]["tallas"]
    colores = maestro_por_id[producto.empresa_id]["colores"]
    inv, creado = get_or_create(
        Inventario, producto_id=producto.id, sucursal_id=sucursal.id,
        talla_id=tallas[talla].id, color_id=colores[color].id,
        defaults={"cantidad_disponible": disponible, "cantidad_reservada": 0,
                  "cantidad_vendida": vendida, "stock_minimo": 5, "activo": True},
    )
    if creado:
        db.add(MovimientoInventario(inventario_id=inv.id, tipo="entrada", cantidad=disponible + vendida,
                                    motivo="Carga inicial de inventario (seed)"))


maestro_por_id = {smartlook.id: maestro["smartlook"], urban.id: maestro["urbanstyle"]}
ps = cargar_productos(smartlook, productos_smartlook, prov_smartlook)
pu = cargar_productos(urban, productos_urban, prov_urban)

# Mezcla de stock disponible, bajo (<= 5) y agotado para que se vean los tres estados.
for i, p in enumerate(ps):
    stock(p, suc_centro, "M", "Negro", [45, 30, 22, 18, 3, 0, 15, 2, 25, 12][i], vendida=8 + i)
    stock(p, suc_norte, "L", "Blanco", [35, 4, 28, 14, 25, 20, 1, 0, 16, 9][i], vendida=5 + i)
    if i % 2 == 0:
        stock(p, suc_equi, "S", "Azul", [24, 19, 32, 21, 16][i // 2], vendida=3 + i)
for i, p in enumerate(pu):
    stock(p, suc_urban, "M", "Negro", [12, 3, 20][i], vendida=4)

DIAS_HISTORIAL = 60
# Lunes..domingo: el fin de semana se vende bastante más (patrón que el modelo de demanda debe aprender).
FACTOR_DIA_SEMANA = [0.7, 0.75, 0.85, 0.95, 1.3, 1.7, 1.1]
PESO_CATEGORIA = {"Camisetas": 1.2, "Pantalones": 1.0, "Chaquetas": 1.3, "Camisas": 0.9, "Vestidos": 1.0}
TENDENCIA_CATEGORIA = {"Camisetas": 0.9, "Vestidos": 0.6, "Chaquetas": -0.8}

print(f"== Historial de ventas y reservas ({DIAS_HISTORIAL} días, para el dashboard y el ML)")


NOMBRES = ["Ana", "Luis", "Carla", "Diego", "Sofía", "Mateo", "Lucía", "Jorge", "Valentina", "Andrés",
           "Camila", "Rodrigo", "Daniela", "Marco", "Paola", "Sergio", "Gabriela", "Iván", "Natalia", "Pablo"]
APELLIDOS = ["Rojas", "Vargas", "Gutiérrez", "Mamani", "Flores", "Suárez", "Justiniano", "Quispe", "Paz", "Ortiz"]


def crear_clientes(empresa, cantidad, dominio):
    """Clientes de prueba (para la segmentación del CU15 hacen falta varios con historial)."""
    rnd = random.Random(empresa.id)
    clientes = []
    for i in range(1, cantidad + 1):
        nombre = f"{rnd.choice(NOMBRES)} {rnd.choice(APELLIDOS)}"
        c, _ = get_or_create(Usuario, email=f"cliente{i:02d}@{dominio}",
                             defaults={"nombre": nombre, "password_hash": _hash_demo,
                                       "rol": "cliente", "empresa_id": empresa.id})
        clientes.append(c)
    print(f"  [+] {empresa.slug}: {cantidad} clientes de prueba")
    return clientes


def perfiles_clientes(clientes, rnd):
    """Cada cliente compra con distinta intensidad, y algunos dejan de comprar (para que haya segmentos reales)."""
    perfiles = []
    for c in clientes:
        tipo = rnd.choices(["vip", "regular", "ocasional", "abandono"], weights=[15, 35, 30, 20])[0]
        peso = {"vip": 6.0, "regular": 2.0, "ocasional": 0.6, "abandono": 2.5}[tipo]
        ultimo_dia = rnd.randint(15, 40) if tipo == "abandono" else 0  # días atrás desde los que ya no compra
        perfiles.append((c, peso * rnd.uniform(0.7, 1.3), ultimo_dia))
    return perfiles


def historial(empresa, productos, sucursales, cajero, clientes, ventas_por_dia):
    """Ventas y reservas pasadas con semilla fija: el dashboard siempre muestra lo mismo."""
    if db.query(Venta).join(Sucursal).filter(Sucursal.empresa_id == empresa.id).first():
        print(f"  [=] {empresa.slug}: ya tiene historial")
        return
    rnd = random.Random(empresa.id * 7919)
    perfiles = perfiles_clientes(clientes, rnd)

    def cliente_para(dias_atras):
        activos = [(c, peso) for c, peso, hasta in perfiles if dias_atras >= hasta]
        return rnd.choices([c for c, _ in activos], weights=[p for _, p in activos])[0]

    tallas = maestro_por_id[empresa.id]["tallas"]
    colores = maestro_por_id[empresa.id]["colores"]
    np_rng = np.random.default_rng(empresa.id)
    ahora = datetime.now(ZONA_HORARIA_LOCAL)
    n_ventas = n_reservas = 0
    for dias_atras in range(DIAS_HISTORIAL - 1, -1, -1):
        dia = ahora - timedelta(days=dias_atras)
        avance = 1 - dias_atras / DIAS_HISTORIAL  # 0 al principio del historial, 1 hoy
        # Patrón semanal marcado (viernes y sábado fuertes) y un leve crecimiento del negocio.
        esperado = ventas_por_dia * FACTOR_DIA_SEMANA[dia.weekday()] * (1 + 0.25 * avance)
        # Estacionalidad: se acerca el verano, suben camisetas y vestidos y bajan las chaquetas.
        pesos_cat = {cat: max(0.2, w + TENDENCIA_CATEGORIA.get(cat, 0) * avance) for cat, w in PESO_CATEGORIA.items()}
        pesos_prod = [pesos_cat.get(p.categoria.nombre, 1.0) for p in productos]
        for sucursal in sucursales:
            for _ in range(int(np_rng.poisson(esperado))):
                momento = dia.replace(hour=rnd.randint(9, 20), minute=rnd.randint(0, 59), second=0, microsecond=0)
                if momento > ahora:
                    continue
                canal = "online" if rnd.random() < 0.3 else "presencial"
                # Las ventas online siempre tienen cliente; en tienda, la mitad se registran con cliente.
                con_cliente = canal == "online" or rnd.random() < 0.5
                venta = Venta(sucursal_id=sucursal.id, canal=canal, estado="completada", total=0,
                              cajero_id=cajero.id if cajero and canal == "presencial" else None,
                              cliente_id=cliente_para(dias_atras).id if con_cliente else None,
                              creada_en=momento)
                total = 0
                elegidos = {rnd.choices(productos, weights=pesos_prod)[0] for _ in range(rnd.randint(1, 3))}
                for producto in elegidos:
                    cantidad = rnd.choices([1, 2, 3], weights=[70, 25, 5])[0]
                    venta.items.append(VentaItem(producto_id=producto.id, cantidad=cantidad,
                                                 precio_unitario=producto.precio,
                                                 talla_id=rnd.choice(list(tallas.values())).id,
                                                 color_id=rnd.choice(list(colores.values())).id))
                    total += float(producto.precio) * cantidad
                venta.total = round(total, 2)
                db.add(venta)
                n_ventas += 1
            if rnd.random() < 0.6:
                reserva = Reserva(cliente_id=cliente_para(dias_atras).id, sucursal_id=sucursal.id,
                                  estado=rnd.choices(["atendida", "confirmada", "pendiente", "cancelada"],
                                                     weights=[50, 20, 15, 15])[0],
                                  creada_en=dia.replace(hour=rnd.randint(9, 20), minute=0, second=0, microsecond=0))
                producto = rnd.choice(productos)
                reserva.items.append(ReservaItem(producto_id=producto.id, cantidad=rnd.randint(1, 2),
                                                 talla_id=rnd.choice(list(tallas.values())).id,
                                                 color_id=rnd.choice(list(colores.values())).id))
                db.add(reserva)
                n_reservas += 1
    print(f"  [+] {empresa.slug}: {n_ventas} ventas y {n_reservas} reservas")


cajero_centro = db.query(Usuario).filter_by(email="cajero.centro@smartlook.bo").first()
clientes_smartlook = crear_clientes(smartlook, 48, "smartlook.bo")
clientes_urban = crear_clientes(urban, 18, "urbanstyle.bo")
historial(smartlook, ps, [suc_centro, suc_norte, suc_equi], cajero_centro, clientes_smartlook, ventas_por_dia=8)
historial(urban, pu, [suc_urban], None, clientes_urban, ventas_por_dia=5)

db.commit()
db.close()

print()
print("Seed listo. Contraseña de todos los usuarios de prueba:", PASSWORD_DEMO)
