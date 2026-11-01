"""Lógica de negocio multi-empresa: empresas (CU2), planes (CU3) y suscripciones (CU4).

Las funciones `suscripcion_vigente` y `verificar_limite` las usan otros módulos
(auth, usuarios, sucursales, catálogo) para hacer cumplir el plan contratado.
"""
from datetime import date, datetime
from typing import Literal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Producto
from app.modules.empresas import models, schemas
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.security import hash_password

Recurso = Literal["sucursales", "usuarios", "productos"]

_NOMBRE_RECURSO = {"sucursales": "sucursales", "usuarios": "usuarios", "productos": "productos"}


def _hoy() -> date:
    return datetime.now(ZONA_HORARIA_LOCAL).date()


# ======================================================================
# Planes (CU3)
# ======================================================================

def listar_planes(db: Session, solo_activos: bool = False) -> list[models.Plan]:
    query = db.query(models.Plan)
    if solo_activos:
        query = query.filter(models.Plan.activo.is_(True))
    return query.order_by(models.Plan.precio_mensual, models.Plan.id).all()


def obtener_plan(db: Session, plan_id: int) -> models.Plan | None:
    return db.query(models.Plan).filter(models.Plan.id == plan_id).first()


def _nombre_plan_disponible(db: Session, nombre: str, excluir_id: int | None = None) -> bool:
    query = db.query(models.Plan).filter(func.lower(models.Plan.nombre) == nombre.strip().lower())
    if excluir_id is not None:
        query = query.filter(models.Plan.id != excluir_id)
    return query.first() is None


def crear_plan(db: Session, data: schemas.PlanCreate) -> models.Plan:
    if not _nombre_plan_disponible(db, data.nombre):
        raise HTTPException(status_code=400, detail="Ya existe un plan con ese nombre")
    plan = models.Plan(**data.model_dump())
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


def actualizar_plan(db: Session, plan_id: int, data: schemas.PlanUpdate) -> models.Plan | None:
    plan = obtener_plan(db, plan_id)
    if not plan:
        return None
    cambios = data.model_dump(exclude_unset=True)
    if "nombre" in cambios and not _nombre_plan_disponible(db, cambios["nombre"], plan.id):
        raise HTTPException(status_code=400, detail="Ya existe un plan con ese nombre")

    # Bajar un límite no puede dejar a una empresa suscrita por encima de lo permitido.
    limites_nuevos = {k: v for k, v in cambios.items() if k.startswith("max_") and v is not None}
    if limites_nuevos:
        for suscripcion in _suscripciones_activas_del_plan(db, plan.id):
            uso = calcular_uso(db, suscripcion.empresa_id)
            for campo, limite in limites_nuevos.items():
                recurso = campo.removeprefix("max_")
                if getattr(uso, recurso).usados > limite:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"La empresa '{suscripcion.empresa.nombre}' ya usa "
                            f"{getattr(uso, recurso).usados} {recurso}; no se puede bajar el límite a {limite}"
                        ),
                    )

    for campo, valor in cambios.items():
        setattr(plan, campo, valor)
    db.commit()
    db.refresh(plan)
    return plan


def desactivar_plan(db: Session, plan_id: int) -> models.Plan | None:
    """Baja lógica: el plan deja de ofrecerse, pero las suscripciones que ya lo usan siguen."""
    plan = obtener_plan(db, plan_id)
    if not plan:
        return None
    plan.activo = False
    db.commit()
    db.refresh(plan)
    return plan


def _suscripciones_activas_del_plan(db: Session, plan_id: int) -> list[models.Suscripcion]:
    return (
        db.query(models.Suscripcion)
        .filter(models.Suscripcion.plan_id == plan_id, models.Suscripcion.estado == "activa")
        .all()
    )


# ======================================================================
# Suscripciones y límites (CU4)
# ======================================================================

def suscripcion_actual(db: Session, empresa_id: int) -> models.Suscripcion | None:
    """La última suscripción no reemplazada (activa, suspendida o cancelada)."""
    return (
        db.query(models.Suscripcion)
        .filter(
            models.Suscripcion.empresa_id == empresa_id,
            models.Suscripcion.estado != "reemplazada",
        )
        .order_by(models.Suscripcion.id.desc())
        .first()
    )


def es_vigente(suscripcion: models.Suscripcion | None) -> bool:
    if suscripcion is None or suscripcion.estado != "activa":
        return False
    return suscripcion.fecha_fin is None or suscripcion.fecha_fin >= _hoy()


def suscripcion_vigente(db: Session, empresa_id: int) -> models.Suscripcion | None:
    suscripcion = suscripcion_actual(db, empresa_id)
    return suscripcion if es_vigente(suscripcion) else None


def calcular_uso(db: Session, empresa_id: int) -> schemas.UsoEmpresa:
    suscripcion = suscripcion_actual(db, empresa_id)
    plan = suscripcion.plan if suscripcion else None

    sucursales = (
        db.query(func.count(Sucursal.id))
        .filter(Sucursal.empresa_id == empresa_id, Sucursal.activa.is_(True))
        .scalar()
    )
    # Los clientes de la tienda no cuentan: el límite es de personal (admin, encargados, cajeros, proveedores).
    usuarios = (
        db.query(func.count(Usuario.id))
        .filter(Usuario.empresa_id == empresa_id, Usuario.activo.is_(True), Usuario.rol != "cliente")
        .scalar()
    )
    productos = (
        db.query(func.count(Producto.id))
        .filter(Producto.empresa_id == empresa_id, Producto.activo.is_(True))
        .scalar()
    )
    return schemas.UsoEmpresa(
        sucursales=schemas.UsoRecurso(usados=sucursales, limite=plan.max_sucursales if plan else None),
        usuarios=schemas.UsoRecurso(usados=usuarios, limite=plan.max_usuarios if plan else None),
        productos=schemas.UsoRecurso(usados=productos, limite=plan.max_productos if plan else None),
    )


def verificar_limite(db: Session, empresa_id: int | None, recurso: Recurso, cantidad: int = 1) -> None:
    """Lanza 403 si la empresa no puede sumar `cantidad` del recurso según su plan.

    Bloquea la fila de la empresa para que dos altas simultáneas no superen el límite.
    """
    if empresa_id is None:
        raise HTTPException(status_code=400, detail="El usuario no pertenece a ninguna empresa")
    db.query(models.Empresa).filter(models.Empresa.id == empresa_id).with_for_update().first()

    suscripcion = suscripcion_vigente(db, empresa_id)
    if suscripcion is None:
        raise HTTPException(status_code=403, detail="La empresa no tiene una suscripción vigente")

    uso = getattr(calcular_uso(db, empresa_id), recurso)
    if uso.limite is not None and uso.usados + cantidad > uso.limite:
        raise HTTPException(
            status_code=403,
            detail=(
                f"Tu plan {suscripcion.plan.nombre} permite hasta {uso.limite} {_NOMBRE_RECURSO[recurso]} "
                f"y ya tenés {uso.usados}. Mejorá el plan para agregar más."
            ),
        )


def _validar_uso_cabe_en_plan(db: Session, empresa_id: int, plan: models.Plan) -> None:
    uso = calcular_uso(db, empresa_id)
    excedidos = [
        f"{recurso} ({getattr(uso, recurso).usados} de {limite})"
        for recurso, limite in (
            ("sucursales", plan.max_sucursales),
            ("usuarios", plan.max_usuarios),
            ("productos", plan.max_productos),
        )
        if limite is not None and getattr(uso, recurso).usados > limite
    ]
    if excedidos:
        raise HTTPException(
            status_code=400,
            detail=f"La empresa supera los límites del plan {plan.nombre}: " + ", ".join(excedidos),
        )


def asignar_plan(db: Session, empresa_id: int, data: schemas.SuscripcionAsignar) -> models.Suscripcion:
    """Asigna o cambia el plan. La suscripción anterior queda como 'reemplazada' (historial)."""
    empresa = (
        db.query(models.Empresa).filter(models.Empresa.id == empresa_id).with_for_update().first()
    )
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    plan = obtener_plan(db, data.plan_id)
    if not plan or not plan.activo:
        raise HTTPException(status_code=400, detail="El plan no existe o no está disponible")
    hoy = _hoy()
    if data.fecha_fin is not None and data.fecha_fin < hoy:
        raise HTTPException(status_code=400, detail="La fecha de fin no puede ser anterior a hoy")

    _validar_uso_cabe_en_plan(db, empresa_id, plan)

    anterior = suscripcion_actual(db, empresa_id)
    if anterior is not None:
        anterior.estado = "reemplazada"
        if anterior.fecha_fin is None or anterior.fecha_fin > hoy:
            anterior.fecha_fin = hoy

    nueva = models.Suscripcion(
        empresa_id=empresa_id,
        plan_id=plan.id,
        estado="activa",
        fecha_inicio=hoy,
        fecha_fin=data.fecha_fin,
    )
    db.add(nueva)
    db.commit()
    db.refresh(nueva)
    return nueva


def cambiar_estado_suscripcion(
    db: Session, empresa_id: int, data: schemas.SuscripcionEstadoUpdate
) -> models.Suscripcion:
    suscripcion = suscripcion_actual(db, empresa_id)
    if suscripcion is None:
        raise HTTPException(status_code=404, detail="La empresa no tiene suscripción")
    if suscripcion.estado == "cancelada" and data.estado != "cancelada":
        raise HTTPException(
            status_code=400, detail="Una suscripción cancelada no se reactiva: asigná un plan nuevo"
        )
    suscripcion.estado = data.estado
    db.commit()
    db.refresh(suscripcion)
    return suscripcion


def historial_suscripciones(db: Session, empresa_id: int) -> list[models.Suscripcion]:
    return (
        db.query(models.Suscripcion)
        .filter(models.Suscripcion.empresa_id == empresa_id)
        .order_by(models.Suscripcion.id.desc())
        .all()
    )


# ======================================================================
# Empresas (CU2)
# ======================================================================

def listar_empresas(db: Session) -> list[models.Empresa]:
    return db.query(models.Empresa).order_by(models.Empresa.id).all()


def obtener_empresa(db: Session, empresa_id: int) -> models.Empresa | None:
    return db.query(models.Empresa).filter(models.Empresa.id == empresa_id).first()


def obtener_empresa_por_slug(db: Session, slug: str) -> models.Empresa | None:
    return db.query(models.Empresa).filter(models.Empresa.slug == slug.strip().lower()).first()


def detalle_empresa(db: Session, empresa: models.Empresa) -> schemas.EmpresaDetalle:
    suscripcion = suscripcion_actual(db, empresa.id)
    return schemas.EmpresaDetalle(
        **schemas.EmpresaOut.model_validate(empresa).model_dump(),
        suscripcion=schemas.SuscripcionOut.model_validate(suscripcion) if suscripcion else None,
        suscripcion_vigente=es_vigente(suscripcion),
        uso=calcular_uso(db, empresa.id),
    )


def crear_empresa(db: Session, data: schemas.EmpresaCreate) -> models.Empresa:
    """Alta de una empresa contratante junto con su plan y su primer administrador."""
    if obtener_empresa_por_slug(db, data.slug):
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese identificador")
    if db.query(Usuario).filter(Usuario.email == data.administrador.email).first():
        raise HTTPException(status_code=400, detail="El email del administrador ya está registrado")
    plan = obtener_plan(db, data.plan_id)
    if not plan or not plan.activo:
        raise HTTPException(status_code=400, detail="El plan no existe o no está disponible")
    if data.fecha_fin is not None and data.fecha_fin < _hoy():
        raise HTTPException(status_code=400, detail="La fecha de fin no puede ser anterior a hoy")

    empresa = models.Empresa(
        **data.model_dump(exclude={"plan_id", "fecha_fin", "administrador"}),
    )
    db.add(empresa)
    try:
        db.flush()
        db.add(
            models.Suscripcion(
                empresa_id=empresa.id,
                plan_id=plan.id,
                estado="activa",
                fecha_inicio=_hoy(),
                fecha_fin=data.fecha_fin,
            )
        )
        db.add(
            Usuario(
                nombre=data.administrador.nombre,
                email=data.administrador.email,
                password_hash=hash_password(data.administrador.password),
                rol="administrador",
                empresa_id=empresa.id,
            )
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="El identificador o el email ya están en uso")
    db.refresh(empresa)
    return empresa


def actualizar_empresa(db: Session, empresa_id: int, data: schemas.EmpresaUpdate) -> models.Empresa | None:
    empresa = obtener_empresa(db, empresa_id)
    if not empresa:
        return None
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(empresa, campo, valor)
    db.commit()
    db.refresh(empresa)
    return empresa


def desactivar_empresa(db: Session, empresa_id: int) -> models.Empresa | None:
    """Baja lógica: sus usuarios dejan de poder iniciar sesión, los datos se conservan."""
    empresa = obtener_empresa(db, empresa_id)
    if not empresa:
        return None
    empresa.activa = False
    db.commit()
    db.refresh(empresa)
    return empresa
