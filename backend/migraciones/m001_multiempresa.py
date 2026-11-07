"""Migración 001 — lleva una base del primer parcial al esquema multi-empresa del segundo parcial.

Pensada para la base compartida de Supabase (o cualquier base creada con la versión anterior):
NO borra datos. Todo lo existente queda asignado a una empresa por defecto ("smartlook").

Qué hace, en UNA transacción (si algo falla, no cambia nada):
  1. Crea las tablas que faltan (empresas, planes, transferencias, modelos_ml, ...).
  2. Agrega las columnas que faltan en las tablas existentes (empresa_id, incluye_ia, logo_url, ...).
  3. Crea la empresa por defecto, los planes (RN-04/RN-05) y su suscripción Profesional.
  4. Asigna empresa_id a usuarios, sucursales, productos, catálogo maestro y proveedores.
  5. Cambia la unicidad de nombres del catálogo maestro: de global a "por empresa".
  6. Agrega claves foráneas, índices y NOT NULL según los modelos.
  7. Crea el superadmin de la plataforma si no existe.

Es idempotente: correrla de nuevo no cambia nada.

Uso (desde la carpeta backend, o dentro del contenedor):
    python -m migraciones.m001_multiempresa --simular      # muestra qué haría, sin tocar nada
    python -m migraciones.m001_multiempresa                # aplica

Para apuntar a otra base sin tocar el .env:  DATABASE_URL=postgresql://... python -m migraciones.m001_multiempresa
"""
import argparse
import sys
from datetime import datetime

from sqlalchemy import inspect, text

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import app.main  # noqa: F401  registra todos los modelos
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.db.session import Base, engine
from app.shared.security import hash_password

EMPRESA_SLUG = "smartlook"
EMPRESA_NOMBRE = "SmartLook Boutique"
SUPERADMIN_EMAIL = "superadmin@smartlook.bo"
SUPERADMIN_PASSWORD = "Demo1234!"  # misma contraseña de prueba que el seed; cambiarla en producción

# nombre, descripción, precio, max_sucursales, max_usuarios, max_productos, incluye_ia
PLANES = [
    ("Básico", "Para una tienda que recién empieza", 199, 2, 5, 50, False),
    ("Profesional", "Varias sucursales, reportes con IA y analítica", 499, 10, 20, 500, True),
    ("Empresarial", "Sin límites", 999, None, None, None, True),
]

# Tablas que pasan a pertenecer a una empresa.
TABLAS_CON_EMPRESA = [
    "sucursales", "usuarios", "productos", "categorias", "tallas",
    "colores", "temporadas", "colecciones", "proveedores", "promociones",
]
# Catálogo maestro: el nombre deja de ser único global y pasa a ser único por empresa.
UNICIDAD_POR_EMPRESA = ["categorias", "tallas", "colores", "temporadas"]


class Migracion:
    def __init__(self, conn, simular: bool):
        self.conn, self.simular, self.pasos = conn, simular, 0

    def ejecutar(self, descripcion: str, sql: str, **params):
        self.pasos += 1
        print(f"  {'[simulado] ' if self.simular else ''}{descripcion}")
        if not self.simular:
            self.conn.execute(text(sql), params)

    def escalar(self, sql: str, **params):
        return self.conn.execute(text(sql), params).scalar()


def _existe_constraint(m: Migracion, nombre: str) -> bool:
    return bool(m.escalar("select 1 from pg_constraint where conname = :n", n=nombre))


def migrar(simular: bool) -> None:
    with engine.begin() as conn:
        m = Migracion(conn, simular)
        insp = inspect(conn)
        existentes = set(insp.get_table_names())

        print("1. Tablas nuevas")
        faltantes = [t for t in Base.metadata.sorted_tables if t.name not in existentes]
        for tabla in faltantes:
            print(f"  {'[simulado] ' if simular else ''}crear tabla {tabla.name}")
        if faltantes and not simular:
            Base.metadata.create_all(bind=conn, tables=faltantes)
        if not faltantes:
            print("  (no falta ninguna)")

        print("2. Columnas nuevas en tablas existentes")
        agregadas = 0
        for tabla in Base.metadata.sorted_tables:
            if tabla.name not in existentes:
                continue
            en_db = {c["name"] for c in insp.get_columns(tabla.name)}
            for col in tabla.columns:
                if col.name in en_db:
                    continue
                tipo = col.type.compile(dialect=conn.dialect)
                # Se agregan nullable: primero se completan los datos y después se aplica NOT NULL.
                default = " DEFAULT false" if tipo.upper() == "BOOLEAN" else ""
                m.ejecutar(f"agregar {tabla.name}.{col.name} ({tipo})",
                           f'ALTER TABLE "{tabla.name}" ADD COLUMN "{col.name}" {tipo}{default}')
                agregadas += 1
        if not agregadas:
            print("  (no falta ninguna)")

        if simular and (faltantes or agregadas):
            print("\n[simulado] Los pasos siguientes dependen de las tablas/columnas de arriba: se aplicarían a continuación.")
            print("  3. empresa por defecto, planes y suscripción | 4. asignar empresa_id | 5. unicidad por empresa")
            print("  6. claves foráneas, índices y NOT NULL | 7. superadmin")
            return

        print("3. Empresa por defecto, planes y suscripción")
        empresa_id = m.escalar("select id from empresas where slug = :s", s=EMPRESA_SLUG)
        if empresa_id is None:
            m.ejecutar(f"crear empresa '{EMPRESA_NOMBRE}' ({EMPRESA_SLUG})",
                       "insert into empresas (nombre, slug, activa) values (:n, :s, true)", n=EMPRESA_NOMBRE, s=EMPRESA_SLUG)
            empresa_id = m.escalar("select id from empresas where slug = :s", s=EMPRESA_SLUG)
        for nombre, desc, precio, suc, usr, prod, ia in PLANES:
            if m.escalar("select id from planes where nombre = :n", n=nombre) is None:
                m.ejecutar(f"crear plan {nombre}",
                           "insert into planes (nombre, descripcion, precio_mensual, max_sucursales, max_usuarios, "
                           "max_productos, incluye_ia, activo) values (:n, :d, :p, :s, :u, :pr, :ia, true)",
                           n=nombre, d=desc, p=precio, s=suc, u=usr, pr=prod, ia=ia)
            elif m.escalar(
                "select 1 from planes where nombre = :n and "
                "(max_sucursales is distinct from :s or incluye_ia is distinct from :ia)",
                n=nombre, s=suc, ia=ia,
            ):
                m.ejecutar(f"actualizar límites e IA del plan {nombre} (RN-04/RN-05)",
                           "update planes set max_sucursales = :s, incluye_ia = :ia where nombre = :n",
                           n=nombre, s=suc, ia=ia)
        if not m.escalar("select 1 from suscripciones where empresa_id = :e", e=empresa_id):
            plan_pro = m.escalar("select id from planes where nombre = 'Profesional'")
            m.ejecutar("suscribir la empresa al plan Profesional (sin vencimiento)",
                       "insert into suscripciones (empresa_id, plan_id, estado, fecha_inicio) values (:e, :p, 'activa', :f)",
                       e=empresa_id, p=plan_pro, f=datetime.now(ZONA_HORARIA_LOCAL).date())

        print("4. Asignar los datos existentes a la empresa")
        for tabla in TABLAS_CON_EMPRESA:
            condicion = " and rol <> 'superadmin'" if tabla == "usuarios" else ""
            pendientes = m.escalar(f'select count(*) from "{tabla}" where empresa_id is null{condicion}')
            if pendientes:
                m.ejecutar(f"{tabla}: {pendientes} fila(s) → empresa {EMPRESA_SLUG}",
                           f'update "{tabla}" set empresa_id = :e where empresa_id is null{condicion}', e=empresa_id)

        print("5. Nombres del catálogo maestro únicos por empresa")
        for tabla in UNICIDAD_POR_EMPRESA:
            viejo, nuevo = f"{tabla}_nombre_key", f"uq_{tabla}_empresa_nombre"
            if _existe_constraint(m, viejo):
                m.ejecutar(f"{tabla}: quitar unicidad global de nombre", f'ALTER TABLE "{tabla}" DROP CONSTRAINT "{viejo}"')
            if not _existe_constraint(m, nuevo):
                m.ejecutar(f"{tabla}: nombre único por empresa",
                           f'ALTER TABLE "{tabla}" ADD CONSTRAINT "{nuevo}" UNIQUE (empresa_id, nombre)')

        print("6. Claves foráneas, índices y NOT NULL")
        for tabla in Base.metadata.sorted_tables:
            if tabla.name not in existentes:
                continue  # las tablas nuevas ya se crearon completas
            for col in tabla.columns:
                for fk in col.foreign_keys:
                    nombre = f"fk_{tabla.name}_{col.name}"
                    ya = m.escalar(
                        "select 1 from information_schema.key_column_usage k join information_schema.table_constraints c "
                        "on c.constraint_name = k.constraint_name where c.constraint_type = 'FOREIGN KEY' "
                        "and k.table_name = :t and k.column_name = :c", t=tabla.name, c=col.name)
                    if not ya:
                        m.ejecutar(f"FK {tabla.name}.{col.name} → {fk.column.table.name}",
                                   f'ALTER TABLE "{tabla.name}" ADD CONSTRAINT "{nombre}" FOREIGN KEY ("{col.name}") '
                                   f'REFERENCES "{fk.column.table.name}" ("{fk.column.name}")')
                if col.index and not col.unique:
                    indice = f"ix_{tabla.name}_{col.name}"
                    if not m.escalar("select 1 from pg_indexes where indexname = :i", i=indice):
                        m.ejecutar(f"índice {indice}", f'CREATE INDEX "{indice}" ON "{tabla.name}" ("{col.name}")')
                if not col.nullable and not col.primary_key:
                    nulo = m.escalar(
                        "select is_nullable from information_schema.columns where table_name = :t and column_name = :c",
                        t=tabla.name, c=col.name)
                    if nulo == "YES":
                        vacios = m.escalar(f'select count(*) from "{tabla.name}" where "{col.name}" is null')
                        if vacios:
                            print(f"  AVISO: {tabla.name}.{col.name} tiene {vacios} fila(s) vacías; se deja nullable")
                        else:
                            m.ejecutar(f"NOT NULL {tabla.name}.{col.name}",
                                       f'ALTER TABLE "{tabla.name}" ALTER COLUMN "{col.name}" SET NOT NULL')

        print("7. Superadmin de la plataforma")
        if m.escalar("select 1 from usuarios where rol = 'superadmin'"):
            print("  (ya existe)")
        elif m.escalar("select 1 from usuarios where email = :e", e=SUPERADMIN_EMAIL):
            print(f"  AVISO: {SUPERADMIN_EMAIL} ya existe con otro rol; crealo a mano")
        else:
            m.ejecutar(f"crear {SUPERADMIN_EMAIL}",
                       "insert into usuarios (nombre, email, password_hash, rol, activo) "
                       "values ('Superadmin SmartLook', :e, :p, 'superadmin', true)",
                       e=SUPERADMIN_EMAIL, p=hash_password(SUPERADMIN_PASSWORD))

        print(f"\n{'SIMULACIÓN: no se cambió nada' if simular else 'Migración aplicada'} ({m.pasos} paso(s)).")
        if simular:
            conn.rollback()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simular", action="store_true", help="mostrar los cambios sin aplicarlos")
    migrar(parser.parse_args().simular)
