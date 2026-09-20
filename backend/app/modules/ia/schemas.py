"""Esquemas Pydantic del módulo ia (CU06/CU20 — recomendaciones y análisis de preferencias,
CU21 — chatbot/asistente virtual)."""
from pydantic import BaseModel


class PreferenciaDetectada(BaseModel):
    tipo: str  # categoria, temporada, coleccion
    nombre: str
    peso: int  # cantidad de unidades reservadas asociadas a esta preferencia


class PerfilPreferencias(BaseModel):
    tiene_historial: bool
    total_reservas_analizadas: int
    preferencias: list[PreferenciaDetectada]


class ProductoRecomendado(BaseModel):
    producto_id: int
    nombre_producto: str
    precio: float
    nombre_categoria: str | None = None
    modelo_ar_url: str | None = None
    imagen_url: str | None = None
    motivo: str
    puntaje: int


class ChatHistorialItem(BaseModel):
    autor: str  # "usuario" o "bot"
    texto: str


class ChatMensajeRequest(BaseModel):
    mensaje: str
    # Turnos previos de esta conversación (los últimos ~6), para que el asistente entienda
    # preguntas de seguimiento como "dame más detalles" sin repetir todo el contexto a mano.
    historial: list[ChatHistorialItem] = []


class ChatMensajeResponse(BaseModel):
    respuesta: str
    intencion: str
    sugerencias: list[str] = []


class ConfiguracionIAOut(BaseModel):
    """Config expuesta al admin. `api_key` nunca se devuelve en texto plano, solo si está seteada."""
    base_url: str
    modelo: str
    api_key_configurada: bool


class ConfiguracionIAUpdate(BaseModel):
    base_url: str
    modelo: str
    # Si viene None o vacío, se conserva la api_key ya guardada (evita tener que reescribirla en cada save).
    api_key: str | None = None


class ConfiguracionIAPrueba(BaseModel):
    ok: bool
    respuesta: str | None = None
    error: str | None = None


class ChatReportesRequest(BaseModel):
    mensaje: str
    historial: list[ChatHistorialItem] = []
    # Solo tiene efecto para el admin (filtra por sucursal); un encargado siempre
    # queda acotado a la suya propia sin importar lo que venga acá.
    sucursal_id: int | None = None


class ChatReportesResponse(BaseModel):
    respuesta: str
    sugerencias: list[str] = []
