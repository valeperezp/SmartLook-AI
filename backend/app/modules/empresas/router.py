"""Endpoints multi-empresa.

- /planes                         CU3 — planes y sus funcionalidades (superadmin). Listado de activos: público.
- /empresas                       CU2 — empresas contratantes: alta, edición, suspensión y reactivación (superadmin).
- /empresas/{id}/suscripcion      CU4 — asignar/cambiar plan, renovar y cambiar estado (superadmin).
- /mi-empresa                     CU4 2a — el administrador consulta su suscripción (solo lectura).
"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.modules.auth.service import ROL_SUPERADMIN, empresa_actual_id, require_roles
from app.modules.empresas import schemas, service
from app.modules.usuarios.models import Usuario
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


def _plan_o_404(plan):
    if not plan:
        raise HTTPException(status_code=404, detail="Plan no encontrado")
    return plan


# ---------------------------------------------------------------- Planes (CU3)

@planes_router.get("", response_model=list[schemas.PlanOut])
def listar_planes_activos(db: Session = Depends(get_db)):
    """Planes que se ofrecen hoy (público)."""
    return service.listar_planes(db, solo_activos=True)


@planes_router.get("/todos", response_model=list[schemas.PlanOut], dependencies=[Depends(superadmin_only)])
def listar_todos_los_planes(db: Session = Depends(get_db)):
    return service.listar_planes(db)


@planes_router.get("/funcionalidades", response_model=list[schemas.FuncionalidadOut],
                   dependencies=[Depends(superadmin_only)])
def listar_funcionalidades(db: Session = Depends(get_db)):
    """Lista de funcionalidades con su casilla de habilitación en el formulario de plan."""
    return service.listar_funcionalidades(db)


@planes_router.post("", response_model=schemas.PlanOut, status_code=201)
def crear_plan(data: schemas.PlanCreate, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    return service.crear_plan(db, data, actor)


@planes_router.put("/{plan_id}", response_model=schemas.PlanOut)
def actualizar_plan(plan_id: int, data: schemas.PlanUpdate, db: Session = Depends(get_db),
                    actor: Usuario = Depends(superadmin_only)):
    return _plan_o_404(service.actualizar_plan(db, plan_id, data, actor))


@planes_router.post("/{plan_id}/desactivar", response_model=schemas.PlanOut)
def desactivar_plan(plan_id: int, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    return _plan_o_404(service.desactivar_plan(db, plan_id, actor))


@planes_router.delete("/{plan_id}", status_code=204)
def eliminar_plan(plan_id: int, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    if not service.eliminar_plan(db, plan_id, actor):
        raise HTTPException(status_code=404, detail="Plan no encontrado")


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


@empresas_router.post("", response_model=schemas.EmpresaCreada, status_code=201)
def crear_empresa(data: schemas.EmpresaCreate, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    empresa, password_temporal = service.crear_empresa(db, data, actor)
    detalle = service.detalle_empresa(db, empresa)
    return schemas.EmpresaCreada(
        **detalle.model_dump(),
        credenciales=schemas.CredencialesAdmin(email=data.administrador.email, password_temporal=password_temporal),
    )


@empresas_router.put("/{empresa_id}", response_model=schemas.EmpresaDetalle)
def actualizar_empresa(empresa_id: int, data: schemas.EmpresaUpdate, db: Session = Depends(get_db),
                       actor: Usuario = Depends(superadmin_only)):
    empresa = service.actualizar_empresa(db, empresa_id, data, actor)
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return service.detalle_empresa(db, empresa)


@empresas_router.post("/{empresa_id}/suspender", response_model=schemas.EmpresaDetalle)
def suspender_empresa(empresa_id: int, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    empresa = service.cambiar_estado_empresa(db, empresa_id, False, actor)
    if not empresa:
        raise HTTPException(status_code=404, detail="Empresa no encontrada")
    return service.detalle_empresa(db, empresa)


@empresas_router.post("/{empresa_id}/reactivar", response_model=schemas.EmpresaDetalle)
def reactivar_empresa(empresa_id: int, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    empresa = service.cambiar_estado_empresa(db, empresa_id, True, actor)
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
    return [service.suscripcion_out(s) for s in service.historial_suscripciones(db, empresa_id)]


@empresas_router.post("/{empresa_id}/suscripcion", response_model=schemas.EmpresaDetalle)
def asignar_plan(empresa_id: int, data: schemas.SuscripcionAsignar, db: Session = Depends(get_db),
                 actor: Usuario = Depends(superadmin_only)):
    service.asignar_plan(db, empresa_id, data, actor)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@empresas_router.post("/{empresa_id}/suscripcion/renovar", response_model=schemas.EmpresaDetalle)
def renovar_suscripcion(empresa_id: int, db: Session = Depends(get_db), actor: Usuario = Depends(superadmin_only)):
    service.renovar_suscripcion(db, empresa_id, actor)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@empresas_router.patch("/{empresa_id}/suscripcion", response_model=schemas.EmpresaDetalle)
def cambiar_estado_suscripcion(
    empresa_id: int, data: schemas.SuscripcionEstadoUpdate, db: Session = Depends(get_db),
    actor: Usuario = Depends(superadmin_only),
):
    service.cambiar_estado_suscripcion(db, empresa_id, data, actor)
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


# ------------------------------------- Mi suscripción (administrador, CU4 2a)

@mi_empresa_router.get("", response_model=schemas.EmpresaDetalle, dependencies=[Depends(admin_only)])
def mi_empresa(empresa_id: int = Depends(empresa_actual_id), db: Session = Depends(get_db)):
    return service.detalle_empresa(db, _empresa_o_404(db, empresa_id))


@mi_empresa_router.get(
    "/suscripciones", response_model=list[schemas.SuscripcionOut], dependencies=[Depends(admin_only)]
)
def mi_historial(empresa_id: int = Depends(empresa_actual_id), db: Session = Depends(get_db)):
    return [service.suscripcion_out(s) for s in service.historial_suscripciones(db, empresa_id)]
