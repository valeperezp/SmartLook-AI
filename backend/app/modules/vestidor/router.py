"""Endpoints HTTP del módulo Vestidor virtual (CU05)."""
import logging
from datetime import datetime, timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.modules.vestidor import schemas, service
from app.modules.vestidor.models import VestidorJob
from app.shared.db.session import SessionLocal, get_db

router = APIRouter(prefix="/vestidor", tags=["vestidor"])
logger = logging.getLogger(__name__)

# Mensajes de negocio que se pueden mostrar tal cual; cualquier otro error del job es interno y se oculta.
_PREFIJOS_ERROR_VISIBLES = ("Replicate", "Timeout", "Job expirado")
_ERROR_GENERICO = "Error en la generación del vestidor. Reintentá."


def _error_para_cliente(error: str | None) -> str | None:
    if not error:
        return error
    if error.startswith(_PREFIJOS_ERROR_VISIBLES):
        return error
    return _ERROR_GENERICO


@router.post(
    "/generar",
    response_model=schemas.VestidorJobCrearResponse,
    status_code=202,
)
async def generar_vestidor(
    background_tasks: BackgroundTasks,
    producto_id: int = Form(...),
    foto: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("cliente", "administrador")),
):
    """Inicia la generación asíncrona del vestidor virtual.

    Devuelve {job_id, estado, mensaje} en < 1 s con HTTP 202.
    La llamada a Replicate se ejecuta en background.
    Consultar el estado en GET /vestidor/job/{job_id}.
    """
    if not foto.content_type or not foto.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="El archivo debe ser una imagen")

    foto_bytes = await foto.read()
    if len(foto_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="La imagen no puede superar los 10MB")

    job = await service.crear_job_vestidor(
        db=db,
        usuario_id=usuario.id,
        producto_id=producto_id,
        foto_usuario=foto_bytes,
    )

    async def _tarea_background(job_id: int, foto: bytes) -> None:
        """Background task: abre su propia sesión de BD, independiente de la request."""
        bg_db = SessionLocal()
        try:
            await service.procesar_job(bg_db, job_id, foto)
        finally:
            bg_db.close()

    background_tasks.add_task(_tarea_background, job.id, foto_bytes)

    respuesta = schemas.VestidorJobCrearResponse(
        job_id=job.id,
        estado=job.estado,
        mensaje="Generación iniciada. Consulta el estado en GET /vestidor/job/{job_id}",
    )
    # Libera la conexion de la request antes de que corra el BackgroundTask: FastAPI cierra get_db
    # recien al terminar las background tasks y el job quedaria reteniendo 2 conexiones del pool.
    db.close()
    return respuesta


@router.get(
    "/job/{job_id}",
    response_model=schemas.VestidorJobEstado,
)
async def consultar_job(
    job_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("cliente", "administrador")),
):
    """Devuelve el estado actual del job de generación del vestidor.

    404 si no existe. 403 si el job no pertenece al usuario.
    """
    job: VestidorJob | None = db.query(VestidorJob).filter(VestidorJob.id == job_id).first()
    if job is None:
        raise HTTPException(status_code=404, detail="Job no encontrado")
    if job.usuario_id != usuario.id:
        raise HTTPException(status_code=403, detail="No tienes acceso a este job")

    # Un job activo sin cambios por mas de 4 min se da por perdido (reinicio del backend, fallo del proveedor).
    if job.estado in ("pendiente", "procesando") and datetime.utcnow() - job.actualizado_en > timedelta(minutes=4):
        job.estado = "fallido"
        job.error = "Job expirado sin respuesta del proveedor IA (timeout)"
        db.commit()
        db.refresh(job)

    return schemas.VestidorJobEstado(
        job_id=job.id,
        estado=job.estado,
        imagen_resultado_url=job.imagen_resultado_url,
        error=_error_para_cliente(job.error),
        producto_id=job.producto_id,
        creado_en=job.creado_en,
        actualizado_en=job.actualizado_en,
    )
