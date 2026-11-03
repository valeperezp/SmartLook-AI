"""Endpoints de analítica con Machine Learning (CU15). Requiere plan con IA (RN-05)."""
from fastapi import APIRouter, Depends, Query
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.modules.analitica_ml import service
from app.modules.auth.service import require_roles
from app.modules.empresas import service as empresas_service
from app.modules.reportes import service as reportes_service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/analitica", tags=["analitica"])

admin_only = require_roles("administrador")
admin_or_encargado = require_roles("administrador", "encargado_sucursal")


@router.get("")
def consultar(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (el encargado ve la suya)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Predicción de demanda, segmentos de clientes y métricas de los últimos modelos entrenados."""
    empresas_service.requiere_plan_con_ia(db, usuario.empresa_id)
    efectiva = reportes_service.sucursal_efectiva(usuario, sucursal_id, db)
    return service.consultar(db, usuario, efectiva)


@router.post("/entrenar")
async def entrenar(usuario: Usuario = Depends(admin_only), db: Session = Depends(get_db)):
    """Genera datos sintéticos si hacen falta, entrena ambos modelos y guarda sus métricas."""
    empresas_service.requiere_plan_con_ia(db, usuario.empresa_id)
    return await run_in_threadpool(service.entrenar, db, usuario)
