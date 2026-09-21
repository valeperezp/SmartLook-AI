"""
Script de un solo uso: genera recortes PNG con fondo transparente de cada producto
(para el vestidor virtual, CU05) a partir de su foto de catálogo, usando rembg
(remoción de fondo local, gratis, sin API key). Sube el resultado a Supabase Storage
y guarda la URL en `producto.modelo_ar_url`.

Uso (dentro del contenedor backend, que ya tiene rembg instalado temporalmente):
    docker compose exec backend python scripts/generar_ar_transparente.py
"""
import io
import uuid

import httpx
from PIL import Image
from rembg import new_session, remove

# isnet-general-use (~176MB) en vez del modelo por defecto de rembg (bria-rmbg-2.0,
# ~1GB, se quedaba sin memoria en el contenedor). Mejor calidad de segmentación que
# u2net para fondos difíciles (ropa oscura contra fondos oscuros/con textura).
_SESSION = new_session("isnet-general-use")

# Umbral de sanidad: si el recorte deja casi toda la imagen opaca (no se sacó fondo)
# o casi toda transparente (se perdió la prenda), el resultado no sirve — mejor no
# guardar nada y que el vestidor caiga a la silueta vectorial de siempre.
_COBERTURA_MIN = 0.03
_COBERTURA_MAX = 0.90

from app.modules.catalogo.models import Producto
from app.shared.core.config import settings
from app.shared.db.session import SessionLocal

# Los modelos usan relationships() con nombres de clase en string, resueltos contra
# TODAS las clases registradas en el Base compartido — hay que importarlas todas
# (igual que hace main.py) o SQLAlchemy no encuentra clases como "Proveedor".
import app.modules.usuarios.models  # noqa: F401
import app.modules.sucursales.models  # noqa: F401
import app.modules.proveedores.models  # noqa: F401
import app.modules.reservas.models  # noqa: F401
import app.modules.inventario.models  # noqa: F401
import app.modules.ia.models  # noqa: F401
import app.modules.ventas.models  # noqa: F401
import app.modules.pagos.models  # noqa: F401
import app.modules.promociones.models  # noqa: F401


def main():
    if not settings.supabase_url or not settings.supabase_service_role_key:
        print("Falta SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY en el .env — no se puede subir nada.")
        return

    db = SessionLocal()
    try:
        productos = db.query(Producto).filter(Producto.activo.is_(True)).all()
        print(f"{len(productos)} productos activos encontrados.")

        for producto in productos:
            if not producto.imagen_url:
                print(f"[{producto.id}] {producto.nombre}: sin imagen_url, se salta.")
                continue

            print(f"[{producto.id}] {producto.nombre}: descargando foto...")
            try:
                resp = httpx.get(producto.imagen_url, timeout=30.0)
                resp.raise_for_status()
            except httpx.HTTPError as exc:
                print(f"  ERROR descargando: {exc}")
                continue

            print(f"  removiendo fondo...")
            try:
                recorte = remove(resp.content, session=_SESSION)
            except Exception as exc:
                print(f"  ERROR en rembg: {exc}")
                producto.modelo_ar_url = None
                db.commit()
                continue

            # rembg devuelve PNG con alpha directamente, pero re-codificamos con Pillow
            # para asegurar que quede como PNG válido y recortar el margen transparente.
            img = Image.open(io.BytesIO(recorte)).convert("RGBA")

            alpha = img.getchannel("A")
            total_px = alpha.width * alpha.height
            opacos_px = sum(1 for a in alpha.getdata() if a > 10)
            cobertura = opacos_px / total_px if total_px else 0

            if cobertura < _COBERTURA_MIN or cobertura > _COBERTURA_MAX:
                print(f"  recorte sospechoso (cobertura {cobertura:.0%}) — se descarta, queda la silueta vectorial.")
                producto.modelo_ar_url = None
                db.commit()
                continue

            bbox = img.getbbox()
            if bbox:
                img = img.crop(bbox)
            buffer = io.BytesIO()
            img.save(buffer, format="PNG")
            contenido_png = buffer.getvalue()

            ruta_archivo = f"ar/producto-{producto.id}-{uuid.uuid4().hex}.png"
            print(f"  subiendo a Supabase ({len(contenido_png) / 1024:.0f} KB)...")
            try:
                resp_upload = httpx.post(
                    f"{settings.supabase_url}/storage/v1/object/{settings.supabase_storage_bucket}/{ruta_archivo}",
                    content=contenido_png,
                    headers={
                        "Authorization": f"Bearer {settings.supabase_service_role_key}",
                        "apikey": settings.supabase_service_role_key,
                        "Content-Type": "image/png",
                    },
                    timeout=30.0,
                )
                resp_upload.raise_for_status()
            except httpx.HTTPError as exc:
                print(f"  ERROR subiendo a Supabase: {exc}")
                continue

            url_publica = (
                f"{settings.supabase_url}/storage/v1/object/public/"
                f"{settings.supabase_storage_bucket}/{ruta_archivo}"
            )
            producto.modelo_ar_url = url_publica
            db.commit()
            print(f"  OK -> {url_publica}")

        print("Listo.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
