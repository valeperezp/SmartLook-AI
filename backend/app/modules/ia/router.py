"""Endpoints HTTP del módulo ia (CU06 — recibir recomendaciones, CU20 — analizar preferencias,
CU21 — interactuar con chatbot/asistente virtual)."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.ia import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/ia", tags=["ia"])

solo_cliente = require_roles("cliente")
solo_admin = require_roles("administrador")


@router.get("/preferencias", response_model=schemas.PerfilPreferencias)
def obtener_preferencias(
    usuario: Usuario = Depends(solo_cliente),
    db: Session = Depends(get_db),
):
    """CU20: perfil de preferencias derivado del historial de reservas del cliente autenticado."""
    return service.analizar_preferencias(db, cliente_id=usuario.id)


@router.get("/recomendaciones", response_model=list[schemas.ProductoRecomendado])
def obtener_recomendaciones(
    limit: int = Query(8, ge=1, le=20),
    usuario: Usuario = Depends(solo_cliente),
    db: Session = Depends(get_db),
):
    """CU06: productos recomendados para el cliente autenticado."""
    return service.generar_recomendaciones(db, cliente_id=usuario.id, limit=limit)


@router.post("/chat", response_model=schemas.ChatMensajeResponse)
def enviar_mensaje_chat(
    data: schemas.ChatMensajeRequest,
    usuario: Usuario = Depends(solo_cliente),
    db: Session = Depends(get_db),
):
    """CU21: procesa un mensaje del cliente y devuelve la respuesta del asistente virtual."""
    historial = [h.model_dump() for h in data.historial]
    return service.procesar_mensaje_chat(db, cliente_id=usuario.id, mensaje=data.mensaje, historial=historial)


# =========================================================================
# Configuración del proveedor de IA (solo admin) — estándar API de OpenAI
# =========================================================================

@router.get("/configuracion", response_model=schemas.ConfiguracionIAOut, dependencies=[Depends(solo_admin)])
def obtener_configuracion(db: Session = Depends(get_db)):
    """Devuelve la configuración actual del proveedor de IA (nunca la api_key en texto plano)."""
    config = service.obtener_configuracion_ia(db)
    return schemas.ConfiguracionIAOut(
        base_url=config.base_url,
        modelo=config.modelo,
        api_key_configurada=bool(config.api_key),
    )


@router.put("/configuracion", response_model=schemas.ConfiguracionIAOut, dependencies=[Depends(solo_admin)])
def actualizar_configuracion(data: schemas.ConfiguracionIAUpdate, db: Session = Depends(get_db)):
    """Actualiza base_url/modelo/api_key del proveedor de IA usado por el chatbot."""
    config = service.actualizar_configuracion_ia(db, data.base_url, data.modelo, data.api_key)
    return schemas.ConfiguracionIAOut(
        base_url=config.base_url,
        modelo=config.modelo,
        api_key_configurada=bool(config.api_key),
    )


@router.post("/configuracion/probar", response_model=schemas.ConfiguracionIAPrueba, dependencies=[Depends(solo_admin)])
def probar_configuracion(db: Session = Depends(get_db)):
    """Envía un mensaje de prueba al proveedor configurado, para validar la conexión desde el panel admin."""
    return service.probar_configuracion_ia(db)
