"""
Lógica del vestidor virtual con IA (CU05) — genera una foto de la persona
"puesta" la prenda real, usando Gemini 2.5 Flash Image ("Nano Banana") como
editor de imágenes: se le pasan la foto de la persona + la foto de catálogo
de la prenda, y devuelve una imagen fotorrealista combinada.

Si GEMINI_API_KEY no está configurada, el endpoint no se registra como
disponible y el frontend sigue funcionando con la silueta dibujada en el
navegador (MediaPipe) — este módulo es un complemento, no un reemplazo duro.
"""
import base64

import httpx
from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.catalogo.models import Producto
from app.shared.core.config import settings

_GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent"

_PROMPT = """Sos un editor fotográfico profesional especializado en fotografía de moda.
Te doy dos imágenes:
1. Una foto de una persona.
2. Una prenda de ropa de catálogo, categoría "{categoria}", llamada "{nombre}".

Generá una única imagen fotorrealista de la MISMA persona de la primera foto (mismo rostro, \
cuerpo, pose, iluminación y fondo) pero vistiendo la prenda de la segunda imagen en el lugar \
correspondiente de su cuerpo, reemplazando la ropa que tenga puesta en esa zona. Mantené todo \
lo demás de la foto original intacto: identidad, pose, fondo e iluminación. Devolvé únicamente \
la imagen resultante, sin texto."""


def generar_prueba_virtual(
    db: Session, producto_id: int, foto_bytes: bytes, foto_mime: str
) -> tuple[str, str]:
    """Devuelve (imagen_base64, mime_type) de la persona probándose la prenda."""
    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=503,
            detail="El vestidor con IA no está configurado en este servidor (falta GEMINI_API_KEY).",
        )

    producto = db.query(Producto).filter(Producto.id == producto_id).first()
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    if not producto.imagen_url:
        raise HTTPException(status_code=400, detail="Ese producto todavía no tiene una foto cargada")

    try:
        resp_prenda = httpx.get(producto.imagen_url, timeout=20.0)
        resp_prenda.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo descargar la foto de la prenda: {exc}")

    prenda_bytes = resp_prenda.content
    prenda_mime = resp_prenda.headers.get("content-type", "image/jpeg").split(";")[0]
    categoria_nombre = producto.categoria.nombre if producto.categoria else "prenda"

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": _PROMPT.format(categoria=categoria_nombre, nombre=producto.nombre)},
                    {"inline_data": {"mime_type": foto_mime, "data": base64.b64encode(foto_bytes).decode()}},
                    {"inline_data": {"mime_type": prenda_mime, "data": base64.b64encode(prenda_bytes).decode()}},
                ]
            }
        ]
    }

    url = _GEMINI_URL.format(modelo=settings.gemini_image_model)
    try:
        resp = httpx.post(url, params={"key": settings.gemini_api_key}, json=payload, timeout=60.0)
        resp.raise_for_status()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=502, detail=f"Gemini rechazó la solicitud: {exc.response.text[:300]}")
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"No se pudo contactar a Gemini: {exc}")

    data = resp.json()
    for candidato in data.get("candidates") or []:
        for parte in candidato.get("content", {}).get("parts", []):
            inline = parte.get("inlineData") or parte.get("inline_data")
            if inline and inline.get("data"):
                mime = inline.get("mimeType") or inline.get("mime_type") or "image/png"
                return inline["data"], mime

    raise HTTPException(
        status_code=502,
        detail="Gemini no devolvió ninguna imagen (puede haber bloqueado el pedido por sus filtros de seguridad).",
    )
