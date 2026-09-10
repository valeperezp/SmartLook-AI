"""Script de inicialización / seed para el módulo de Inventario y datos base."""
import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from app.shared.db.session import SessionLocal
import app.modules.proveedores.models  # Requerido para mapeo de relaciones en Producto
from app.modules.catalogo.models import Categoria, Talla, Color, Temporada, Coleccion, Producto
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.modules.inventario.models import Inventario, MovimientoInventario

db = SessionLocal()


def get_or_create(model, defaults=None, **kwargs):
    instance = db.query(model).filter_by(**kwargs).first()
    if instance:
        return instance, False
    params = dict(kwargs)
    if defaults:
        params.update(defaults)
    instance = model(**params)
    db.add(instance)
    db.commit()
    db.refresh(instance)
    return instance, True


print("==================================================")
print("   INICIANDO SEED SMARTLOOK AI — INVENTARIO")
print("==================================================")

# -------------------------------------------------------------
# PASO A: Arreglar color con nombre vacío (ID=2)
# -------------------------------------------------------------
color_vacio = db.query(Color).filter(Color.id == 2).first()
if color_vacio and (not color_vacio.nombre or color_vacio.nombre.strip() == ""):
    color_vacio.nombre = "Blanco"
    color_vacio.hex = "#FFFFFF"
    db.commit()
    print("[OK] Color ID=2 arreglado: ahora se llama 'Blanco' (#FFFFFF)")
elif color_vacio:
    print(f"[INFO] Color ID=2 verificado: '{color_vacio.nombre}' ({color_vacio.hex})")

# -------------------------------------------------------------
# PASO B: Completar Tallas
# -------------------------------------------------------------
print("\n--- PASO B: COMPLETAR TALLAS ---")
tallas_nombres = ["XS", "S", "L", "XL"]
for nombre in tallas_nombres:
    t, created = get_or_create(Talla, nombre=nombre)
    print(f"{'[OK] Creada' if created else '[--] Ya existe'} talla: {t.nombre} (ID={t.id})")

tallas_map = {t.nombre: t.id for t in db.query(Talla).all()}
colores_map = {c.nombre: c.id for c in db.query(Color).all()}

# Asegurar color Azul si no existe para mayor variedad
c_azul, _ = get_or_create(Color, nombre="Azul", defaults={"hex": "#0000FF", "activo": True})
colores_map[c_azul.nombre] = c_azul.id

# -------------------------------------------------------------
# PASO C: Completar Categorías y Productos hasta llegar a 10
# -------------------------------------------------------------
print("\n--- PASO C: COMPLETAR PRODUCTOS ---")
temporada_default = db.query(Temporada).first()
coleccion_default = db.query(Coleccion).first()
proveedor_default = db.query(app.modules.proveedores.models.Proveedor).first()

temp_id = temporada_default.id if temporada_default else None
col_id = coleccion_default.id if coleccion_default else None
prov_id = proveedor_default.id if proveedor_default else None

# Asegurar categorías
cat_pantalones, _ = get_or_create(Categoria, nombre="Pantalones", defaults={"activo": True})
cat_chaquetas, _ = get_or_create(Categoria, nombre="Chaquetas", defaults={"activo": True})
cat_camisas, _ = get_or_create(Categoria, nombre="Camisas", defaults={"activo": True})
cat_vestidos, _ = get_or_create(Categoria, nombre="Vestidos", defaults={"activo": True})
cat_camisetas = db.query(Categoria).filter(Categoria.nombre == "Camisetas").first()

nuevos_productos = [
    {
        "nombre": "Pantalon Denim Clasico",
        "descripcion": "Jeans corte recto 100% algodon resistente.",
        "precio": 220.00,
        "categoria_id": cat_pantalones.id,
    },
    {
        "nombre": "Pantalon Chino Beige",
        "descripcion": "Pantalon casual comodo para oficina y diario.",
        "precio": 195.00,
        "categoria_id": cat_pantalones.id,
    },
    {
        "nombre": "Chaqueta Cuero Urbana",
        "descripcion": "Chaqueta de cuero sintetico con cremallera metalica.",
        "precio": 450.00,
        "categoria_id": cat_chaquetas.id,
    },
    {
        "nombre": "Chaqueta Bomber Negra",
        "descripcion": "Chaqueta acolchada ligera ideal para media estacion.",
        "precio": 380.00,
        "categoria_id": cat_chaquetas.id,
    },
    {
        "nombre": "Camisa Casual Manga Larga",
        "descripcion": "Camisa de lino transpirable corte regular fit.",
        "precio": 160.00,
        "categoria_id": cat_camisas.id,
    },
    {
        "nombre": "Camisa Oxford Celeste",
        "descripcion": "Camisa formal formal oxford con cuello abotonado.",
        "precio": 175.00,
        "categoria_id": cat_camisas.id,
    },
    {
        "nombre": "Vestido Midi Floral",
        "descripcion": "Vestido ligero estampado floral con lazo a la cintura.",
        "precio": 280.00,
        "categoria_id": cat_vestidos.id,
    },
    {
        "nombre": "Vestido Gala Elegante",
        "descripcion": "Vestido de noche largo con escote refinado.",
        "precio": 490.00,
        "categoria_id": cat_vestidos.id,
    },
]

for p_data in nuevos_productos:
    defaults = {
        "descripcion": p_data["descripcion"],
        "precio": p_data["precio"],
        "categoria_id": p_data["categoria_id"],
        "temporada_id": temp_id,
        "coleccion_id": col_id,
        "proveedor_id": prov_id,
        "activo": True,
    }
    prod, created = get_or_create(Producto, defaults=defaults, nombre=p_data["nombre"])
    print(f"{'[OK] Creado' if created else '[--] Ya existe'} producto: {prod.nombre} (ID={prod.id})")

productos = db.query(Producto).all()
print(f"\nTotal productos en catálogo: {len(productos)}")

# -------------------------------------------------------------
# PASO D: Generar Inventario variado en las 3 sucursales
# -------------------------------------------------------------
print("\n--- PASO D: GENERAR INVENTARIO VARIADO ---")
sucursales = db.query(Sucursal).all()
id_suc_centro = sucursales[0].id if len(sucursales) > 0 else 1
id_suc_norte = sucursales[1].id if len(sucursales) > 1 else 2
id_suc_equipetrol = sucursales[2].id if len(sucursales) > 2 else 3

id_talla_s = tallas_map.get("S")
id_talla_m = tallas_map.get("M")
id_talla_l = tallas_map.get("L")
id_talla_xl = tallas_map.get("XL")

id_col_negro = colores_map.get("Negro")
id_col_blanco = colores_map.get("Blanco")
id_col_rojo = colores_map.get("rojo") or colores_map.get("Rojo")
id_col_azul = colores_map.get("Azul")

# Matriz de prueba combinando productos con stock Disponible, Bajo y Agotado
items_inventario_seed = [
    # --- Sucursal Centro (ID 1) ---
    # Disponibles
    {"prod": productos[0].id, "suc": id_suc_centro, "talla": id_talla_m, "col": id_col_negro, "disp": 45, "res": 3, "vend": 12, "min": 5},
    {"prod": productos[0].id, "suc": id_suc_centro, "talla": id_talla_l, "col": id_col_blanco, "disp": 30, "res": 1, "vend": 8, "min": 5},
    {"prod": productos[1].id, "suc": id_suc_centro, "talla": id_talla_s, "col": id_col_blanco, "disp": 22, "res": 2, "vend": 5, "min": 5},
    {"prod": productos[2].id, "suc": id_suc_centro, "talla": id_talla_m, "col": id_col_azul, "disp": 18, "res": 0, "vend": 7, "min": 5},
    {"prod": productos[4].id, "suc": id_suc_centro, "talla": id_talla_l, "col": id_col_negro, "disp": 15, "res": 2, "vend": 4, "min": 5},
    # Stock Bajo (<= 5)
    {"prod": productos[2].id, "suc": id_suc_centro, "talla": id_talla_s, "col": id_col_azul, "disp": 3, "res": 1, "vend": 15, "min": 5},
    {"prod": productos[6].id, "suc": id_suc_centro, "talla": id_talla_m, "col": id_col_blanco, "disp": 2, "res": 0, "vend": 10, "min": 5},
    # Agotados (disp = 0)
    {"prod": productos[3].id, "suc": id_suc_centro, "talla": id_talla_xl, "col": id_col_negro, "disp": 0, "res": 0, "vend": 20, "min": 5},
    {"prod": productos[8].id, "suc": id_suc_centro, "talla": id_talla_s, "col": id_col_rojo, "disp": 0, "res": 1, "vend": 14, "min": 5},

    # --- Sucursal Norte (ID 2) ---
    # Disponibles
    {"prod": productos[0].id, "suc": id_suc_norte, "talla": id_talla_m, "col": id_col_negro, "disp": 35, "res": 4, "vend": 16, "min": 5},
    {"prod": productos[1].id, "suc": id_suc_norte, "talla": id_talla_m, "col": id_col_blanco, "disp": 28, "res": 0, "vend": 9, "min": 5},
    {"prod": productos[3].id, "suc": id_suc_norte, "talla": id_talla_m, "col": id_col_negro, "disp": 14, "res": 1, "vend": 6, "min": 5},
    {"prod": productos[5].id, "suc": id_suc_norte, "talla": id_talla_l, "col": id_col_azul, "disp": 25, "res": 3, "vend": 11, "min": 5},
    {"prod": productos[7].id, "suc": id_suc_norte, "talla": id_talla_s, "col": id_col_azul, "disp": 20, "res": 0, "vend": 4, "min": 5},
    # Stock Bajo
    {"prod": productos[4].id, "suc": id_suc_norte, "talla": id_talla_m, "col": id_col_negro, "disp": 4, "res": 1, "vend": 18, "min": 5},
    {"prod": productos[9].id, "suc": id_suc_norte, "talla": id_talla_m, "col": id_col_rojo, "disp": 1, "res": 0, "vend": 8, "min": 5},
    # Agotados
    {"prod": productos[2].id, "suc": id_suc_norte, "talla": id_talla_l, "col": id_col_azul, "disp": 0, "res": 0, "vend": 25, "min": 5},

    # --- Sucursal Equipetrol (ID 3) ---
    # Disponibles
    {"prod": productos[2].id, "suc": id_suc_equipetrol, "talla": id_talla_m, "col": id_col_azul, "disp": 24, "res": 2, "vend": 8, "min": 5},
    {"prod": productos[4].id, "suc": id_suc_equipetrol, "talla": id_talla_l, "col": id_col_negro, "disp": 19, "res": 1, "vend": 5, "min": 5},
    {"prod": productos[6].id, "suc": id_suc_equipetrol, "talla": id_talla_m, "col": id_col_blanco, "disp": 32, "res": 0, "vend": 14, "min": 5},
    {"prod": productos[7].id, "suc": id_suc_equipetrol, "talla": id_talla_m, "col": id_col_azul, "disp": 21, "res": 2, "vend": 9, "min": 5},
    {"prod": productos[9].id, "suc": id_suc_equipetrol, "talla": id_talla_s, "col": id_col_rojo, "disp": 16, "res": 1, "vend": 3, "min": 5},
    # Stock Bajo
    {"prod": productos[0].id, "suc": id_suc_equipetrol, "talla": id_talla_s, "col": id_col_blanco, "disp": 3, "res": 0, "vend": 22, "min": 5},
    {"prod": productos[1].id, "suc": id_suc_equipetrol, "talla": id_talla_l, "col": id_col_blanco, "disp": 2, "res": 1, "vend": 12, "min": 5},
    # Agotados
    {"prod": productos[5].id, "suc": id_suc_equipetrol, "talla": id_talla_s, "col": id_col_azul, "disp": 0, "res": 0, "vend": 16, "min": 5},
]

creados_count = 0
existentes_count = 0

for item in items_inventario_seed:
    inv, created = get_or_create(
        Inventario,
        producto_id=item["prod"],
        sucursal_id=item["suc"],
        talla_id=item["talla"],
        color_id=item["col"],
        defaults={
            "cantidad_disponible": item["disp"],
            "cantidad_reservada": item["res"],
            "cantidad_vendida": item["vend"],
            "stock_minimo": item["min"],
            "activo": True,
        },
    )
    if created:
        creados_count += 1
        # Registrar movimiento inicial de entrada
        mov = MovimientoInventario(
            inventario_id=inv.id,
            tipo="entrada",
            cantidad=item["disp"] + item["vend"],
            motivo="Carga inicial de inventario (seed)",
        )
        db.add(mov)
    else:
        existentes_count += 1

db.commit()

print(f"\n[OK] Inventarios creados: {creados_count}")
print(f"[--] Inventarios ya existentes: {existentes_count}")

# -------------------------------------------------------------
# RESUMEN FINAL
# -------------------------------------------------------------
total_inv = db.query(Inventario).count()
total_mov = db.query(MovimientoInventario).count()
print("\n==================================================")
print(f"SEED COMPLETADO EXITOSAMENTE")
print(f"Total registros en 'inventario':            {total_inv}")
print(f"Total registros en 'movimiento_inventario': {total_mov}")
print("==================================================")

db.close()
