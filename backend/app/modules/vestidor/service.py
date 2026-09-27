"""
Lógica del vestidor virtual con IA (CU05) — genera una foto fotorrealista de la
persona probándose la prenda, usando Replicate (IDM-VTON): se le pasan la foto
de la persona + la foto de catálogo de la prenda, y devuelve la imagen combinada.

Presupuesto acotado ($4 ≈ 80 generaciones en Replicate) — hay un límite diario
por usuario que protege el presupuesto, obligatorio.

Arquitectura asíncrona (Fase 1):
  - crear_job_vestidor(): valida y crea el job en BD (< 1 s).
  - procesar_job():       llama a Replicate en background y actualiza el job.
  - generar_prueba_virtual(): wrapper síncrono legado (conservado).
"""
import base64
from datetime import datetime

import replicate
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.modules.catalogo.models import Producto
from app.modules.vestidor.models import VestidorGeneracion, VestidorJob
from app.shared.core.config import settings

_MODELO_IDM_VTON = (
    "cuuupid/idm-vton:906425dbca90663ff5427624839572cc56ea7d380343d13e2a4c4b09d3f0c30f"
)


# ─────────────────────────────────────────────
# Helpers internos
# ─────────────────────────────────────────────

def _construir_human_img(foto_usuario: bytes) -> str:
    foto_b64 = base64.b64encode(foto_usuario).decode()
    return "data:image/jpeg;base64," + foto_b64


def _llamar_replicate_sync(human_img: str, producto: Producto) -> str:
    """Llamada bloqueante a Replicate — ejecutar siempre en threadpool."""
    client = replicate.Client(api_token=settings.replicate_api_token)
    output = client.run(
        _MODELO_IDM_VTON,
        input={
            "human_img": human_img,
            "garm_img": producto.imagen_url,
            "garment_des": producto.nombre,
            "category": "upper_body",
        },
    )
    if hasattr(output, "url"):
        return str(output.url)
    if isinstance(output, str):
        return output
    if isinstance(output, list) and output:
        first = output[0]
        return str(getattr(first, "url", first))
    return str(output)


def _contar_generaciones_hoy(db: Session, usuario_id: int) -> int:
    """Suma jobs (cualquier estado) + generaciones legado creadas hoy."""
    hoy = datetime.utcnow().date()
    jobs = (
        db.query(VestidorJob)
        .filter(
            VestidorJob.usuario_id == usuario_id,
            func.date(VestidorJob.creado_en) == hoy,
        )
        .count()
    )
    legado = (
        db.query(VestidorGeneracion)
        .filter(
            VestidorGeneracion.usuario_id == usuario_id,
            func.date(VestidorGeneracion.creado_en) == hoy,
        )
        .count()
    )
    return jobs + legado


# ─────────────────────────────────────────────
# API asíncrona (Fase 1)
# ─────────────────────────────────────────────

async def crear_job_vestidor(
    db: Session, usuario_id: int, producto_id: int, foto_usuario: bytes
) -> VestidorJob:
    """Valida la request, crea el VestidorJob en estado 'pendiente' y lo devuelve.

    Nunca llama a Replicate — responde en < 1 s.
    """
    if not settings.replicate_api_token:
        raise HTTPException(status_code=503, detail="REPLICATE_API_TOKEN no configurado")

    # Límite diario — suma jobs y generaciones legado
    count = _contar_generaciones_hoy(db, usuario_id)
    if count >= settings.vestidor_max_por_usuario_dia:
        raise HTTPException(
            status_code=429,
            detail=f"Limite diario alcanzado ({settings.vestidor_max_por_usuario_dia} por dia)",
        )

    producto = db.query(Producto).filter(Producto.id == producto_id).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    if not producto.imagen_url:
        raise HTTPException(status_code=400, detail="El producto no tiene imagen")

    job = VestidorJob(
        usuario_id=usuario_id,
        producto_id=producto_id,
        estado="pendiente",
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


async def procesar_job(db: Session, job_id: int, foto_usuario: bytes) -> None:
    """Llama a Replicate y actualiza el VestidorJob en BD.

    Diseñada para ejecutarse en background (BackgroundTasks de FastAPI).
    Nunca propaga excepciones — los errores quedan registrados en job.error.
    La sesión `db` debe ser una NUEVA sesión abierta por la background task.
    """
    job = db.query(VestidorJob).filter(VestidorJob.id == job_id).first()
    if job is None:
        return  # job inexistente, nada que hacer

    # Marcar como procesando
    job.estado = "procesando"
    db.commit()

    try:
        producto = db.query(Producto).filter(Producto.id == job.producto_id).first()
        if not producto or not producto.imagen_url:
            raise ValueError("Producto no encontrado o sin imagen")

        human_img = _construir_human_img(foto_usuario)

        def _run() -> str:
            return _llamar_replicate_sync(human_img, producto)

        result_url = await run_in_threadpool(_run)

        job.estado = "completado"
        job.imagen_resultado_url = result_url

    except Exception as exc:
        job.estado = "fallido"
        job.error = str(exc)

    finally:
        db.commit()


# ─────────────────────────────────────────────
# Wrapper legado (conservado, no modificar)
# ─────────────────────────────────────────────

async def generar_prueba_virtual(
    db: Session, usuario_id: int, producto_id: int, foto_usuario: bytes
) -> dict:
    if not settings.replicate_api_token:
        raise HTTPException(status_code=503, detail="REPLICATE_API_TOKEN no configurado")

    # Límite diario por usuario — protege el presupuesto de Replicate.
    hoy = datetime.utcnow().date()
    count = (
        db.query(VestidorGeneracion)
        .filter(
            VestidorGeneracion.usuario_id == usuario_id,
            func.date(VestidorGeneracion.creado_en) == hoy,
        )
        .count()
    )
    if count >= settings.vestidor_max_por_usuario_dia:
        raise HTTPException(
            status_code=429,
            detail=f"Limite diario alcanzado ({settings.vestidor_max_por_usuario_dia} por dia)",
        )

    producto = db.query(Producto).filter(Producto.id == producto_id).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    if not producto.imagen_url:
        raise HTTPException(status_code=400, detail="El producto no tiene imagen")

    human_img = _construir_human_img(foto_usuario)

    try:
        result_url = await run_in_threadpool(
            lambda: _llamar_replicate_sync(human_img, producto)
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Error con Replicate: {exc}")

    gen = VestidorGeneracion(
        usuario_id=usuario_id,
        producto_id=producto_id,
        imagen_resultado_url=result_url,
    )
    db.add(gen)
    db.commit()

    return {
        "imagen_resultado_url": result_url,
        "producto_id": producto_id,
        "producto_nombre": producto.nombre,
        "desde_cache": False,
    }
