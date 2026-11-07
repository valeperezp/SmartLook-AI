"""
Configuración global de la aplicación, cargada desde variables de entorno.
Cualquier módulo que necesite settings importa desde aquí (no duplicar env vars).
"""
from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "SmartLook-AI API"
    environment: str = "development"

    database_url: str = "postgresql://usuario:password@localhost:5432/smartlook_ai"

    secret_key: str = "cambia-esto-por-una-clave-segura"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    # Multi-empresa (CU1): tienda donde caen los registros que no indican empresa
    # (por ejemplo, la app móvil de clientes).
    empresa_por_defecto: str = "smartlook"

    stripe_secret_key: str = ""
    stripe_publishable_key: str = ""
    # URL pública del backend para armar los enlaces a /uploads. En Render se toma sola de
    # RENDER_EXTERNAL_URL (la define la plataforma), salvo que se indique UPLOADS_BASE_URL.
    uploads_base_url: str = Field(
        default="http://localhost:8000", validation_alias=AliasChoices("UPLOADS_BASE_URL", "RENDER_EXTERNAL_URL")
    )
    uploads_dir: str = "/app/uploads"

    # Chatbot (CU21) — modelo local vía Ollama, corriendo en la máquina host (no en Docker).
    ollama_base_url: str = "http://host.docker.internal:11434"
    ollama_model: str = "llama3.2:latest"

    # Supabase Storage — subida de imágenes de productos. La service_role key SOLO se usa
    # en el backend (bypassa RLS); nunca debe exponerse al frontend.
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_storage_bucket: str = "productos"

    # Vestidor virtual móvil (CU05) — Replicate (IDM-VTON), pago por uso. Presupuesto
    # acotado ($4 ≈ 80 generaciones): cache 24h + límite diario por usuario obligatorios.
    replicate_api_token: str = ""
    vestidor_max_por_usuario_dia: int = 15

    # Orígenes permitidos por CORS, separados por coma. En local alcanza con el
    # frontend de Docker/ng serve; en producción se agrega la URL de Vercel.
    cors_origins: str = "http://localhost:4200"

    model_config = SettingsConfigDict(env_file=(".env", "backend/.env", "../backend/.env"), extra="ignore")

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
