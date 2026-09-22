"""
Lógica del vestidor virtual con IA (CU05) — genera una foto fotorrealista de la
persona probándose la prenda, usando Replicate (IDM-VTON): se le pasan la foto
de la persona + la foto de catálogo de la prenda, y devuelve la imagen combinada.

Presupuesto acotado ($4 ≈ 80 generaciones en Replicate) — por eso hay cache de
24h por (usuario, producto) y un límite diario por usuario, ambos obligatorios.
"""
import base64
from datetime import datetime, timedelta

import replicate
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from app.modules.catalogo.models import Producto
from app.modules.vestidor.models import VestidorGeneracion
from app.shared.core.config import settings

_MODELO_IDM_VTON = (
    "cuuupid/idm-vton:906425dbca90663ff5427624839572cc56ea7d380343d13e2a4c4b09d3f0c30f"
)


async def generar_prueba_virtual(
    db: Session, usuario_id: int, producto_id: int, foto_usuario: bytes
) -> dict:
    if not settings.replicate_api_token:
        raise HTTPException(status_code=503, detail="REPLICATE_API_TOKEN no configurado")

    # Cache: misma combinación (usuario, producto) generada en las últimas 24h —
    # evita gastar una generación de Replicate si el usuario vuelve a probarse
    # la misma prenda.
    cache = (
        db.query(VestidorGeneracion)
        .filter(
            VestidorGeneracion.usuario_id == usuario_id,
            VestidorGeneracion.producto_id == producto_id,
            VestidorGeneracion.creado_en > datetime.utcnow() - timedelta(hours=24),
        )
        .first()
    )
    if cache:
        producto = db.query(Producto).filter(Producto.id == producto_id).first()
        return {
            "imagen_resultado_url": cache.imagen_resultado_url,
            "producto_id": producto_id,
            "producto_nombre": producto.nombre if producto else "",
            "desde_cache": True,
        }

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

    foto_b64 = base64.b64encode(foto_usuario).decode()
    human_img = "data:image/jpeg;base64," + foto_b64

    def _llamar_replicate() -> str:
        # replicate.Client.run(...) es una llamada HTTP bloqueante — se ejecuta
        # en un threadpool (ver abajo) para no trabar el event loop de FastAPI.
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
        return output if isinstance(output, str) else output[0]

    try:
        result_url = await run_in_threadpool(_llamar_replicate)
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
