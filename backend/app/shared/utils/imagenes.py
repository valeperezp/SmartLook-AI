"""Validacion de imagenes subidas por el usuario (contenido real, no solo el content-type declarado)."""
from fastapi import HTTPException

MAX_IMAGEN_BYTES = 10 * 1024 * 1024  # 10 MB


def detectar_tipo_imagen(contenido: bytes) -> tuple[str, str] | None:
    """Devuelve (content_type, extension) segun los magic bytes, o None si no es PNG/JPEG/WEBP."""
    if contenido.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if contenido.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if contenido[:4] == b"RIFF" and contenido[8:12] == b"WEBP":
        return "image/webp", "webp"
    return None


def validar_imagen(contenido: bytes, max_bytes: int = MAX_IMAGEN_BYTES) -> tuple[str, str]:
    """Valida tamano y firma del archivo. Lanza 400 si no es una imagen PNG/JPEG/WEBP valida.

    Devuelve (content_type, extension) detectados del contenido.
    """
    if not contenido:
        raise HTTPException(status_code=400, detail="El archivo esta vacio")
    if len(contenido) > max_bytes:
        raise HTTPException(status_code=400, detail=f"El archivo supera los {max_bytes // (1024 * 1024)} MB")
    tipo = detectar_tipo_imagen(contenido)
    if tipo is None:
        raise HTTPException(
            status_code=400,
            detail="El contenido del archivo no es una imagen valida. Usa PNG, JPG o WEBP",
        )
    return tipo
