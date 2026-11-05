"""Migración 002 — alinea la base con el documento del segundo parcial (CU1–CU7, CU14, CU15, CU19).

Primero aplica la migración 001 (tablas y columnas nuevas, de forma genérica: bitácora, funcionalidades,
plan_funcionalidad, producto_variantes, duración del plan, pago simulado, observaciones de transferencias,
modelo de ML guardado en la base, ...). Después, en UNA transacción:
  1. Crea las funcionalidades de los planes (reportes con IA, analítica con ML, transferencias).
  2. Habilita las funcionalidades de cada plan existente según lo que ya tenía (incluye_ia).
  3. Completa la duración de los planes que no la tienen (30 días; Empresarial 365).
  4. Hace único el NIT de las empresas (si no hay repetidos).
  5. Registra como variantes las combinaciones de producto + talla + color que ya tienen inventario.

NO borra datos y es idempotente: correrla de nuevo no cambia nada.

Uso (desde la carpeta backend, o dentro del contenedor):
    python -m migraciones.m002_alineacion_documento --simular
    python -m migraciones.m002_alineacion_documento
"""
import argparse
import sys

from sqlalchemy import text

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from migraciones import m001_multiempresa  # noqa: E402  (registra los modelos)
from app.modules.catalogo import service as catalogo_service  # noqa: E402
from app.modules.empresas import models as empresas_models  # noqa: E402
from app.modules.empresas import service as empresas_service  # noqa: E402
from app.shared.db.session import SessionLocal  # noqa: E402

DURACION_POR_PLAN = {"empresarial": 365}


def migrar(simular: bool) -> None:
    print("== Migración 001 (estructura)")
    m001_multiempresa.migrar(simular)
    if simular:
        print("\n[simulado] La 002 se aplica sobre la estructura de la 001; corré sin --simular para verla.")
        return

    print("\n== Migración 002 (datos del documento)")
    db = SessionLocal()
    pasos = 0
    try:
        print("1. Funcionalidades de los planes")
        antes = db.query(empresas_models.Funcionalidad).count()
        empresas_service.asegurar_funcionalidades(db)
        nuevas = db.query(empresas_models.Funcionalidad).count() - antes
        print(f"  {nuevas} creada(s)" if nuevas else "  (ya existían)")
        pasos += nuevas

        print("2. Funcionalidades habilitadas por plan")
        for plan in db.query(empresas_models.Plan).all():
            if plan.plan_funcionalidades:
                continue
            codigos = ["transferencias"] + (["reportes_ia", "analitica_ml"] if plan.incluye_ia else [])
            empresas_service._aplicar_funcionalidades(db, plan, codigos)
            print(f"  {plan.nombre}: {', '.join(codigos)}")
            pasos += 1

        print("3. Duración de los planes")
        for plan in db.query(empresas_models.Plan).filter(empresas_models.Plan.duracion_dias.is_(None)).all():
            plan.duracion_dias = DURACION_POR_PLAN.get(plan.nombre.lower(), 30)
            print(f"  {plan.nombre}: {plan.duracion_dias} días")
            pasos += 1

        print("4. NIT único por empresa")
        existe = db.execute(text(
            "select 1 from pg_indexes where tablename = 'empresas' and indexdef ilike '%unique%(nit)%'"
        )).first() or db.execute(text(
            "select 1 from pg_constraint where conname = 'empresas_nit_key'"
        )).first()
        if existe:
            print("  (ya es único)")
        else:
            repetidos = db.execute(text(
                "select nit from empresas where nit is not null group by nit having count(*) > 1"
            )).all()
            if repetidos:
                print(f"  AVISO: hay NIT repetidos ({', '.join(r[0] for r in repetidos)}); se deja sin índice único")
            else:
                db.execute(text("alter table empresas add constraint empresas_nit_key unique (nit)"))
                print("  índice único creado")
                pasos += 1

        print("5. Variantes de producto desde el inventario")
        db.flush()
        creadas = catalogo_service.variantes_desde_inventario(db)
        print(f"  {creadas} variante(s) creada(s)" if creadas else "  (no falta ninguna)")
        pasos += creadas

        db.commit()
        print(f"\nMigración 002 aplicada ({pasos} paso(s)).")
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--simular", action="store_true", help="mostrar los cambios sin aplicarlos")
    migrar(parser.parse_args().simular)
