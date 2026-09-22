"""Endpoints HTTP del módulo Vestidor virtual (CU05)."""
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.usuarios.models import Usuario
from app.modules.vestidor import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/vestidor", tags=["vestidor"])


@router.post("/generar", response_model=schemas.VestidorPruebaOut)
async def generar_vestidor(
    producto_id: int = Form(...),
    foto: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(require_roles("cliente", "administrador")),
):
    """Genera una foto fotorrealista de la persona probándose la prenda (Replicate/IDM-VTON)."""
    if not foto.content_type or not foto.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="El archivo debe ser una imagen")

    foto_bytes = await foto.read()
    if len(foto_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="La imagen no puede superar los 10MB")

    return await service.generar_prueba_virtual(
        db=db,
        usuario_id=usuario.id,
        producto_id=producto_id,
        foto_usuario=foto_bytes,
    )
