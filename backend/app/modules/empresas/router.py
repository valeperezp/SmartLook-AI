"""Endpoints multi-empresa.

- /planes            CU3 — CRUD de planes (superadmin). Listado de activos: público.
- /empresas          CU2 — CRUD de empresas contratantes (superadmin).
- /empresas/{id}/suscripcion   CU4 — asignar/cambiar plan y estado (superadmin).
- /mi-empresa        CU4 — el administrador ve su plan, su uso y puede cambiar de plan.
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import ROL_SUPERADMIN, empresa_actual_id, require_roles
from app.modules.empresas import schemas, service
from app.shared.db.session import get_db

superadmin_only = require_roles(ROL_SUPERADMIN)
admin_only = require_roles("administrador")

planes_router = APIRouter(prefix="/planes", tags=["planes"])
empresas_router = APIRouter(prefix="/empresas", tags=["empresas"])
mi_empresa_router = APIRouter(prefix="/mi-empresa", tags=["empresas"])


def _empresa_o_404(db: Session, empresa_id: int):
    empresa = service.obtener_empresa(db, empresa_id)
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return empresa


# ---------------------------------------------------------------- Planes (CU3)

@planes_router.get("", response_model=list[schemas.PlanOut])
def listar_planes_activos(db: Session = Depends(get_db)):
    """Planes que se ofrecen hoy (público: lo usa la pantalla de cambio de plan)."""
    return service.listar_planes(db, solo_activos=True)


@planes_router.get("/todos", response_model=list[schemas.PlanOut], dependencies=[Depends(superadmin_only)])
def listar_todos_los_planes(db: Session = Depends(get_db)):
    return service.listar_planes(db)


@planes_router.post("", response_model=schemas.PlanOut, status_code=201, dependencies=[Depends(superadmin_only)])
def crear_plan(data: schemas.PlanCreate, db: Session = Depends(get_db)):
    return service.crear_plan(db, data)


@planes_router.put("/{plan_id}", response_model=schemas.PlanOut, dependencies=[Depends(superadmin_only)])
def actualizar_plan(plan_id: int, data: schemas.PlanUpdate, db: Session = Depends(get_db)):
    plan = service.actualizar_plan(db, plan_id, data)
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")
    return plan


@planes_router.delete("/{plan_id}", response_model=schemas.PlanOut, dependencies=[Depends(superadmin_only)])
def desactivar_plan(plan_id: int, db: Session = Depends(get_db)):
    plan = service.desactivar_plan(db, plan_id)
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")
    return plan


# -------------------------------------------------------------- Empresas (CU2)

@empresas_router.get("/publica/{slug}", response_model=schemas.EmpresaPublica)
def empresa_publica(slug: str, db: Session = Depends(get_db)):
    """Nombre de la empresa para mostrar en el login antes de autenticarse."""
    empresa = service.obtener_empresa_por_slug(db, slug)
    if not empresa or not empresa.activa:
        raise HTTPException(status_code=404, detail="No existe una empresa con ese identificador")
    return empresa


@empresas_router.get("", response_model=list[schemas.EmpresaDetalle], dependencies=[Depends(superadmin_only)])
def listar_empresas(db: Session = Depends(get_db)):
    return [service.detalle_empresa(db, e) for e in service.listar_empresas(db)]


@empresas_router.get("/{empresa_id}", response_model=schemas.EmpresaDetalle, dependencies=[Depends(superadmin_only)])
def obtener_empresa(empresa_id: int, db: Session = Depends(get_db)):
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@empresas_router.post("", response_model=schemas.EmpresaDetalle, status_code=201, dependencies=[Depends(superadmin_only)])
def crear_empresa(data: schemas.EmpresaCreate, db: Session = Depends(get_db)):
    return service.detalle_empresa(db, service.crear_empresa(db, data))


@empresas_router.put("/{empresa_id}", response_model=schemas.EmpresaDetalle, dependencies=[Depends(superadmin_only)])
def actualizar_empresa(empresa_id: int, data: schemas.EmpresaUpdate, db: Session = Depends(get_db)):
    empresa = service.actualizar_empresa(db, empresa_id, data)
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return service.detalle_empresa(db, empresa)


@empresas_router.delete("/{empresa_id}", response_model=schemas.EmpresaDetalle, dependencies=[Depends(superadmin_only)])
def desactivar_empresa(empresa_id: int, db: Session = Depends(get_db)):
    empresa = service.desactivar_empresa(db, empresa_id)
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return service.detalle_empresa(db, empresa)


# ------------------------------------------------- Suscripción de empresa (CU4)

@empresas_router.get(
    "/{empresa_id}/suscripciones",
    response_model=list[schemas.SuscripcionOut],
    dependencies=[Depends(superadmin_only)],
)
def historial_suscripciones(empresa_id: int, db: Session = Depends(get_db)):
    _empresa_o_404(db, empresa_id)
    return service.historial_suscripciones(db, empresa_id)


@empresas_router.post(
    "/{empresa_id}/suscripcion",
    response_model=schemas.EmpresaDetalle,
    dependencies=[Depends(superadmin_only)],
)
def asignar_plan(empresa_id: int, data: schemas.SuscripcionAsignar, db: Session = Depends(get_db)):
    service.asignar_plan(db, empresa_id, data)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@empresas_router.patch(
    "/{empresa_id}/suscripcion",
    response_model=schemas.EmpresaDetalle,
    dependencies=[Depends(superadmin_only)],
)
def cambiar_estado_suscripcion(
    empresa_id: int, data: schemas.SuscripcionEstadoUpdate, db: Session = Depends(get_db)
):
    service.cambiar_estado_suscripcion(db, empresa_id, data)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


# ------------------------------------------- Mi empresa (administrador, CU4)

@mi_empresa_router.get("", response_model=schemas.EmpresaDetalle, dependencies=[Depends(admin_only)])
def mi_empresa(empresa_id: int = Depends(empresa_actual_id), db: Session = Depends(get_db)):
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@mi_empresa_router.get(
    "/suscripciones", response_model=list[schemas.SuscripcionOut], dependencies=[Depends(admin_only)]
)
def mi_historial(empresa_id: int = Depends(empresa_actual_id), db: Session = Depends(get_db)):
    return service.historial_suscripciones(db, empresa_id)


@mi_empresa_router.post("/suscripcion", response_model=schemas.EmpresaDetalle, dependencies=[Depends(admin_only)])
def cambiar_mi_plan(
    data: schemas.SuscripcionAsignar,
    empresa_id: int = Depends(empresa_actual_id),
    db: Session = Depends(get_db),
):
    """El administrador cambia el plan de su empresa (sube o baja, validando el uso actual)."""
    service.asignar_plan(db, empresa_id, data)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))
