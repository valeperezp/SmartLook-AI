"""Lógica de negocio multi-empresa: empresas (CU2), planes (CU3) y suscripciones (CU4).

Las funciones `suscripcion_vigente`, `verificar_limite` y `requiere_funcionalidad` las usan otros
módulos (auth, usuarios, sucursales, catálogo, reportes, analítica) para hacer cumplir el plan.
Cada acción del superadmin queda en la bitácora.
"""
import re
import secrets
import unicodedata
from datetime import date, datetime, timedelta
from typing import Literal

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.bitacora import service as bitacora
from app.modules.catalogo.models import Producto
from app.modules.empresas import models, schemas
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.core.tiempo import ZONA_HORARIA_LOCAL
from app.shared.security import hash_password

Recurso = Literal["sucursales", "usuarios", "productos"]

DIAS_AVISO_VENCIMIENTO = 7  # RN-08

# Funcionalidades que un plan puede habilitar (CU3). Se crean solas si faltan.
FUNCIONALIDADES = [
    ("reportes_ia", "Reportes generativos con IA", "Pedir reportes en lenguaje natural, escritos o por voz (CU14)"),
    ("analitica_ml", "Dashboard analítico con Machine Learning",
     "Predicción de demanda y segmentación de clientes (CU15)"),
    ("transferencias", "Transferencias entre sucursales", "Solicitar, enviar y recibir prendas entre sucursales (CU19)"),
]
MSG_SIN_FUNCIONALIDAD = {
    "reportes_ia": "Los reportes generativos están disponibles en el plan Profesional",
    "analitica_ml": "El dashboard analítico está disponible en el plan Profesional",
    "transferencias": "Tu plan no incluye transferencias entre sucursales",
}


def _hoy() -> date:
    return datetime.now(ZONA_HORARIA_LOCAL).date()


# ======================================================================
# Funcionalidades (CU3)
# ======================================================================

def asegurar_funcionalidades(db: Session) -> list[models.Funcionalidad]:
    existentes = {f.codigo: f for f in db.query(models.Funcionalidad).all()}
    for codigo, nombre, descripcion in FUNCIONALIDADES:
        if codigo not in existentes:
            f = models.Funcionalidad(codigo=codigo, nombre=nombre, descripcion=descripcion, activo=True)
            db.add(f)
            existentes[codigo] = f
    db.flush()
    return [existentes[c] for c, _, _ in FUNCIONALIDADES if existentes[c].activo]


def listar_funcionalidades(db: Session) -> list[models.Funcionalidad]:
    lista = asegurar_funcionalidades(db)
    db.commit()
    return lista


def _aplicar_funcionalidades(db: Session, plan: models.Plan, codigos: list[str]) -> None:
    disponibles = {f.codigo: f for f in asegurar_funcionalidades(db)}
    desconocidas = sorted(set(codigos) - set(disponibles))
    if desconocidas:
        raise HTTPException(status_code=400, detail=f"Funcionalidad desconocida: {', '.join(desconocidas)}")
    actuales = {pf.funcionalidad.codigo if pf.funcionalidad else None: pf for pf in plan.plan_funcionalidades}
    for codigo, f in disponibles.items():
        habilitada = codigo in codigos
        if codigo in actuales:
            actuales[codigo].habilitado = habilitada
        elif habilitada:
            plan.plan_funcionalidades.append(models.PlanFuncionalidad(funcionalidad=f, habilitado=True))
    plan.incluye_ia = "reportes_ia" in codigos  # se mantiene por compatibilidad


def plan_tiene(plan: models.Plan | None, codigo: str) -> bool:
    return plan is not None and plan.tiene(codigo)


def requiere_funcionalidad(db: Session, empresa_id: int, codigo: str) -> None:
    """RF-05 / RN-05: el plan de la empresa tiene que incluir la funcionalidad."""
    suscripcion = suscripcion_actual(db, empresa_id)
    if not plan_tiene(suscripcion.plan if suscripcion else None, codigo):
        raise HTTPException(status_code=403, detail=MSG_SIN_FUNCIONALIDAD.get(codigo, "Tu plan no incluye esta función"))


def requiere_plan_con_ia(db: Session, empresa_id: int) -> None:
    """RN-05 (se mantiene el nombre por compatibilidad): analítica con ML."""
    requiere_funcionalidad(db, empresa_id, "analitica_ml")


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


def _validar_limites(valores: dict) -> None:
    """CU3 6a."""
    for campo in ("duracion_dias", "max_sucursales", "max_usuarios", "max_productos"):
        valor = valores.get(campo)
        if valor is not None and valor <= 0:
            raise HTTPException(status_code=400, detail=schemas.MSG_LIMITE)


def _resumen_plan(plan: models.Plan) -> str:
    suc = "sin límite" if plan.max_sucursales is None else plan.max_sucursales
    dur = "sin vencimiento" if plan.duracion_dias is None else f"{plan.duracion_dias} días"
    return f"{plan.nombre}: sucursales {suc}, {dur}, funcionalidades [{', '.join(plan.funcionalidades) or 'ninguna'}]"


def crear_plan(db: Session, data: schemas.PlanCreate, actor: Usuario | None = None) -> models.Plan:
    _validar_limites(data.model_dump())
    if not _nombre_plan_disponible(db, data.nombre):
        raise HTTPException(status_code=400, detail="Ya existe un plan con ese nombre")
    plan = models.Plan(**data.model_dump(exclude={"funcionalidades"}))
    db.add(plan)
    db.flush()
    _aplicar_funcionalidades(db, plan, data.funcionalidades)
    db.flush()
    bitacora.registrar(db, "plan.crear", _resumen_plan(plan), usuario=actor)
    db.commit()
    db.refresh(plan)
    return plan


def _empresas_que_superan(db: Session, plan_id: int, limites: dict) -> list[str]:
    """CU3 paso 7: empresas con este plan que ya usan más de lo que permitiría el nuevo límite."""
    afectadas = []
    for suscripcion in _suscripciones_activas_del_plan(db, plan_id):
        uso = calcular_uso(db, suscripcion.empresa_id)
        excesos = [
            f"{getattr(uso, campo.removeprefix('max_')).usados} {campo.removeprefix('max_')}"
            for campo, limite in limites.items()
            if limite is not None and getattr(uso, campo.removeprefix("max_")).usados > limite
        ]
        if excesos:
            afectadas.append(f"{suscripcion.empresa.nombre} ({', '.join(excesos)})")
    return afectadas


def actualizar_plan(db: Session, plan_id: int, data: schemas.PlanUpdate, actor: Usuario | None = None) -> models.Plan | None:
    plan = obtener_plan(db, plan_id)
    if not plan:
        return None
    cambios = data.model_dump(exclude_unset=True)
    _validar_limites(cambios)
    if "nombre" in cambios and not _nombre_plan_disponible(db, cambios["nombre"], plan.id):
        raise HTTPException(status_code=400, detail="Ya existe un plan con ese nombre")

    limites_nuevos = {k: v for k, v in cambios.items() if k.startswith("max_") and v is not None}
    if limites_nuevos:
        afectadas = _empresas_que_superan(db, plan.id, limites_nuevos)
        if afectadas:  # 7a: no se guarda el cambio
            raise HTTPException(
                status_code=400,
                detail="No se guardó el cambio. Estas empresas superan el nuevo límite: " + "; ".join(afectadas),
            )

    funcionalidades = cambios.pop("funcionalidades", None)
    for campo, valor in cambios.items():
        setattr(plan, campo, valor)
    if funcionalidades is not None:
        _aplicar_funcionalidades(db, plan, funcionalidades)
    db.flush()
    bitacora.registrar(db, "plan.editar", _resumen_plan(plan), usuario=actor)
    db.commit()
    db.refresh(plan)
    return plan


def desactivar_plan(db: Session, plan_id: int, actor: Usuario | None = None) -> models.Plan | None:
    """El plan deja de ofrecerse para nuevas contrataciones; las suscripciones que lo usan siguen."""
    plan = obtener_plan(db, plan_id)
    if not plan:
        return None
    plan.activo = False
    bitacora.registrar(db, "plan.desactivar", plan.nombre, usuario=actor)
    db.commit()
    db.refresh(plan)
    return plan


def eliminar_plan(db: Session, plan_id: int, actor: Usuario | None = None) -> bool:
    """CU3 2b: no se elimina un plan con empresas suscritas (ni con historial)."""
    plan = obtener_plan(db, plan_id)
    if not plan:
        return False
    empresas = (
        db.query(func.count(func.distinct(models.Suscripcion.empresa_id)))
        .filter(models.Suscripcion.plan_id == plan.id)
        .scalar()
    )
    if empresas:
        raise HTTPException(
            status_code=400,
            detail=(
                f"No se puede eliminar el plan {plan.nombre}: {empresas} empresa(s) lo tienen o lo tuvieron contratado. "
                "Desactívelo para que no se ofrezca en nuevas contrataciones."
            ),
        )
    nombre = plan.nombre
    db.delete(plan)
    bitacora.registrar(db, "plan.eliminar", nombre, usuario=actor)
    db.commit()
    return True


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


def dias_para_vencer(suscripcion: models.Suscripcion | None) -> int | None:
    if suscripcion is None or suscripcion.fecha_fin is None:
        return None
    return (suscripcion.fecha_fin - _hoy()).days


def esta_vencida(suscripcion: models.Suscripcion | None) -> bool:
    """RN-06: activa pero con la fecha de vencimiento ya pasada (la empresa entra, pero solo consulta)."""
    dias = dias_para_vencer(suscripcion)
    return suscripcion is not None and suscripcion.estado == "activa" and dias is not None and dias < 0


def estado_mostrado(suscripcion: models.Suscripcion) -> str:
    """CU4 2b: 'vencida' en lugar de 'vigente' si la fecha ya pasó."""
    if suscripcion.estado == "activa":
        return "vencida" if esta_vencida(suscripcion) else "vigente"
    return {"reemplazada": "cerrada"}.get(suscripcion.estado, suscripcion.estado)


def suscripcion_out(suscripcion: models.Suscripcion) -> schemas.SuscripcionOut:
    salida = schemas.SuscripcionOut.model_validate(suscripcion)
    salida.estado_mostrado = estado_mostrado(suscripcion)
    return salida


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
    """RF-05: lanza 403 si la empresa no puede sumar `cantidad` del recurso según su plan.

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
                f"Su plan {suscripcion.plan.nombre} permite hasta {uso.limite} {recurso} activas "
                f"y ya tiene {uso.usados}." if recurso == "sucursales" else
                f"Su plan {suscripcion.plan.nombre} permite hasta {uso.limite} {recurso} y ya tiene {uso.usados}."
            ),
        )


def _validar_uso_cabe_en_plan(db: Session, empresa_id: int, plan: models.Plan) -> None:
    """CU4 paso 7 y 7a (RN-07)."""
    uso = calcular_uso(db, empresa_id)
    if plan.max_sucursales is not None and uso.sucursales.usados > plan.max_sucursales:
        sobran = uso.sucursales.usados - plan.max_sucursales
        raise HTTPException(
            status_code=400,
            detail=f"Debe desactivar {sobran} sucursal{'es' if sobran != 1 else ''} antes de cambiar a este plan",
        )
    for recurso, limite in (("usuarios", plan.max_usuarios), ("productos", plan.max_productos)):
        usados = getattr(uso, recurso).usados
        if limite is not None and usados > limite:
            raise HTTPException(
                status_code=400,
                detail=f"Debe desactivar {usados - limite} {recurso} antes de cambiar a este plan",
            )


def _vencimiento(plan: models.Plan, inicio: date) -> date | None:
    """CU4 paso 6."""
    return inicio + timedelta(days=plan.duracion_dias) if plan.duracion_dias else None


def _cerrar(suscripcion: models.Suscripcion | None, hasta: date) -> None:
    if suscripcion is None:
        return
    suscripcion.estado = "reemplazada"
    if suscripcion.fecha_fin is None or suscripcion.fecha_fin > hasta:
        suscripcion.fecha_fin = hasta


def asignar_plan(
    db: Session, empresa_id: int, data: schemas.SuscripcionAsignar, actor: Usuario | None = None
) -> models.Suscripcion:
    """CU4: asigna o cambia el plan. La suscripción anterior queda cerrada en el historial."""
    empresa = (
        db.query(models.Empresa).filter(models.Empresa.id == empresa_id).with_for_update().first()
    )
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    plan = obtener_plan(db, data.plan_id)
    if not plan or not plan.activo:
        raise HTTPException(status_code=400, detail="El plan no existe o no está disponible")
    hoy = _hoy()
    inicio = data.fecha_inicio or hoy
    fin = _vencimiento(plan, inicio)
    if fin is not None and fin < hoy:
        raise HTTPException(status_code=400, detail="Con esa fecha de inicio la suscripción ya estaría vencida")

    _validar_uso_cabe_en_plan(db, empresa_id, plan)

    anterior = suscripcion_actual(db, empresa_id)
    _cerrar(anterior, hoy)
    nueva = models.Suscripcion(
        empresa_id=empresa_id,
        plan_id=plan.id,
        estado="activa",
        fecha_inicio=inicio,
        fecha_fin=fin,
        monto_pagado=plan.precio_mensual if data.monto_pagado is None else data.monto_pagado,
        metodo_pago_simulado=data.metodo_pago_simulado,
    )
    db.add(nueva)
    accion = "suscripcion.cambiar_plan" if anterior else "suscripcion.asignar"
    vence = fin.strftime("%d/%m/%Y") if fin else "sin vencimiento"
    bitacora.registrar(
        db, accion,
        f"{empresa.nombre}: plan {plan.nombre} desde {inicio.strftime('%d/%m/%Y')}, vence {vence}"
        + (f" (antes: {anterior.plan.nombre})" if anterior else ""),
        usuario=actor, empresa_id=empresa_id,
    )
    db.commit()
    db.refresh(nueva)
    return nueva


def renovar_suscripcion(db: Session, empresa_id: int, actor: Usuario | None = None) -> models.Suscripcion:
    """CU4 3a: extiende el vencimiento por la duración del plan actual y mantiene el plan."""
    empresa = (
        db.query(models.Empresa).filter(models.Empresa.id == empresa_id).with_for_update().first()
    )
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    actual = suscripcion_actual(db, empresa_id)
    if actual is None:
        raise HTTPException(status_code=400, detail="La empresa no tiene suscripción: asígnele un plan")
    if actual.estado == "cancelada":
        raise HTTPException(status_code=400, detail="Una suscripción cancelada no se renueva: asigne un plan")
    plan = actual.plan
    if not plan.duracion_dias or actual.fecha_fin is None:
        raise HTTPException(status_code=400, detail="La suscripción actual no tiene vencimiento: no hace falta renovarla")

    hoy = _hoy()
    # Si todavía no venció, la renovación empieza al día siguiente del vencimiento actual.
    inicio = actual.fecha_fin + timedelta(days=1) if actual.fecha_fin >= hoy else hoy
    fin = _vencimiento(plan, inicio)
    actual.estado = "reemplazada"  # queda en el historial con sus fechas
    nueva = models.Suscripcion(
        empresa_id=empresa_id, plan_id=plan.id, estado="activa",
        fecha_inicio=inicio, fecha_fin=fin,
        monto_pagado=plan.precio_mensual, metodo_pago_simulado=actual.metodo_pago_simulado or "transferencia",
    )
    db.add(nueva)
    bitacora.registrar(
        db, "suscripcion.renovar",
        f"{empresa.nombre}: plan {plan.nombre} renovado hasta {fin.strftime('%d/%m/%Y')}",
        usuario=actor, empresa_id=empresa_id,
    )
    db.commit()
    db.refresh(nueva)
    return nueva


def cambiar_estado_suscripcion(
    db: Session, empresa_id: int, data: schemas.SuscripcionEstadoUpdate, actor: Usuario | None = None
) -> models.Suscripcion:
    suscripcion = suscripcion_actual(db, empresa_id)
    if suscripcion is None:
        raise HTTPException(status_code=404, detail="La empresa no tiene suscripción")
    if suscripcion.estado == "cancelada" and data.estado != "cancelada":
        raise HTTPException(
            status_code=400, detail="Una suscripción cancelada no se reactiva: asigne un plan nuevo"
        )
    anterior = suscripcion.estado
    suscripcion.estado = data.estado
    bitacora.registrar(
        db, "suscripcion.estado", f"{suscripcion.empresa.nombre}: {anterior} → {data.estado}",
        usuario=actor, empresa_id=empresa_id,
    )
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
    dias = dias_para_vencer(suscripcion)
    plan = suscripcion.plan if suscripcion else None
    funcionalidades = [
        schemas.FuncionalidadOut.model_validate(pf.funcionalidad)
        for pf in (plan.plan_funcionalidades if plan else [])
        if pf.habilitado and pf.funcionalidad.activo
    ]
    return schemas.EmpresaDetalle(
        **schemas.EmpresaOut.model_validate(empresa).model_dump(),
        suscripcion=suscripcion_out(suscripcion) if suscripcion else None,
        suscripcion_vigente=es_vigente(suscripcion),
        uso=calcular_uso(db, empresa.id),
        dias_para_vencer=dias,
        aviso_vencimiento=(
            suscripcion is not None and suscripcion.estado == "activa"
            and dias is not None and 0 <= dias <= DIAS_AVISO_VENCIMIENTO
        ),
        solo_lectura=esta_vencida(suscripcion),
        funcionalidades=funcionalidades,
    )


def _nit_disponible(db: Session, nit: str, excluir_id: int | None = None) -> bool:
    query = db.query(models.Empresa).filter(func.lower(models.Empresa.nit) == nit.strip().lower())
    if excluir_id is not None:
        query = query.filter(models.Empresa.id != excluir_id)
    return query.first() is None


def _slug_desde(nombre: str) -> str:
    base = unicodedata.normalize("NFKD", nombre).encode("ascii", "ignore").decode().lower()
    base = re.sub(r"[^a-z0-9]+", "-", base).strip("-")[:50] or "empresa"
    return base


def _slug_libre(db: Session, base: str) -> str:
    slug, n = base, 2
    while obtener_empresa_por_slug(db, slug):
        slug, n = f"{base}-{n}", n + 1
    return slug


def crear_empresa(db: Session, data: schemas.EmpresaCreate, actor: Usuario | None = None) -> tuple[models.Empresa, str | None]:
    """CU2: alta de la empresa con su administrador. Devuelve la empresa y la contraseña temporal generada."""
    if not _nit_disponible(db, data.nit):
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese NIT")  # 6a
    if db.query(Usuario).filter(func.lower(Usuario.email) == data.administrador.email.strip().lower()).first():
        raise HTTPException(status_code=400, detail="El correo ya está en uso")  # 6b
    if data.slug and obtener_empresa_por_slug(db, data.slug):
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese identificador")
    plan = None
    if data.plan_id is not None:
        plan = obtener_plan(db, data.plan_id)
        if not plan or not plan.activo:
            raise HTTPException(status_code=400, detail="El plan no existe o no está disponible")

    password_temporal = None if data.administrador.password else secrets.token_urlsafe(9)
    empresa = models.Empresa(
        **data.model_dump(exclude={"slug", "plan_id", "fecha_inicio", "administrador"}),
        slug=data.slug or _slug_libre(db, _slug_desde(data.nombre)),
        activa=True,
    )
    db.add(empresa)
    try:
        db.flush()
        db.add(
            Usuario(
                nombre=data.administrador.nombre,
                email=data.administrador.email.strip(),
                password_hash=hash_password(data.administrador.password or password_temporal),
                rol="administrador",
                empresa_id=empresa.id,
            )
        )
        bitacora.registrar(
            db, "empresa.crear",
            f"{empresa.nombre} (NIT {empresa.nit}); administrador {data.administrador.email}; "
            "credenciales de acceso enviadas al administrador",
            usuario=actor, empresa_id=empresa.id,
        )
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="El NIT, el identificador o el correo ya están en uso")
    db.refresh(empresa)
    if plan is not None:
        asignar_plan(db, empresa.id, schemas.SuscripcionAsignar(plan_id=plan.id, fecha_inicio=data.fecha_inicio), actor)
    return empresa, password_temporal


def actualizar_empresa(
    db: Session, empresa_id: int, data: schemas.EmpresaUpdate, actor: Usuario | None = None
) -> models.Empresa | None:
    empresa = obtener_empresa(db, empresa_id)
    if not empresa:
        return None
    cambios = data.model_dump(exclude_unset=True)
    if cambios.get("nit") and not _nit_disponible(db, cambios["nit"], empresa.id):
        raise HTTPException(status_code=400, detail="Ya existe una empresa con ese NIT")
    for campo, valor in cambios.items():
        setattr(empresa, campo, valor)
    bitacora.registrar(db, "empresa.editar", f"{empresa.nombre}: {', '.join(cambios) or 'sin cambios'}",
                       usuario=actor, empresa_id=empresa.id)
    db.commit()
    db.refresh(empresa)
    return empresa


def cambiar_estado_empresa(db: Session, empresa_id: int, activa: bool, actor: Usuario | None = None) -> models.Empresa | None:
    """CU2 2b (suspender) y 2c (reactivar). Suspendida: sus usuarios no inician sesión; los datos se conservan."""
    empresa = obtener_empresa(db, empresa_id)
    if not empresa:
        return None
    if empresa.activa == activa:
        raise HTTPException(status_code=400, detail=f"La empresa ya está {'activa' if activa else 'suspendida'}")
    empresa.activa = activa
    bitacora.registrar(db, "empresa.reactivar" if activa else "empresa.suspender", empresa.nombre,
                       usuario=actor, empresa_id=empresa.id)
    db.commit()
    db.refresh(empresa)
    return empresa
