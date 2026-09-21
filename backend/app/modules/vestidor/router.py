"""Endpoints HTTP del módulo Vestidor virtual (CU05)."""
from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.orm import Session

from app.modules.auth.service import get_current_user
from app.modules.usuarios.models import Usuario
from app.modules.vestidor import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/vestidor", tags=["vestidor"])


@router.post("/generar", response_model=schemas.VestidorPruebaOut)
async def generar_prueba_virtual(
    producto_id: int = Form(...),
    foto: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(get_current_user),
):
    """Genera una foto fotorrealista de la persona probándose la prenda (Gemini/Nano Banana)."""
    contenido = await foto.read()
    imagen_base64, mime_type = service.generar_prueba_virtual(
        db, producto_id, contenido, foto.content_type or "image/jpeg"
    )
    return schemas.VestidorPruebaOut(imagen_base64=imagen_base64, mime_type=mime_type)
