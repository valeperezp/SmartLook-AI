"""
Configuración global de la aplicación, cargada desde variables de entorno.
Cualquier módulo que necesite settings importa desde aquí (no duplicar env vars).
"""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "SmartLook-AI API"
    environment: str = "development"

    database_url: str = "postgresql://usuario:password@localhost:5432/smartlook_ai"

    secret_key: str = "cambia-esto-por-una-clave-segura"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60

    stripe_secret_key: str = ""
    stripe_publishable_key: str = ""
    ai_api_key: str = ""  # (sin uso actualmente) reservado por si se vuelve a un proveedor de IA en la nube
    uploads_base_url: str = "http://localhost:8000"
    uploads_dir: str = "/app/uploads"

    # Chatbot (CU21) — modelo local vía Ollama, corriendo en la máquina host (no en Docker).
    ollama_base_url: str = "http://host.docker.internal:11434"
    ollama_model: str = "llama3.2:1b"

    # Supabase Storage — subida de imágenes de productos. La service_role key SOLO se usa
    # en el backend (bypassa RLS); nunca debe exponerse al frontend.
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_storage_bucket: str = "productos"

    # Vestidor virtual (CU05) — Gemini 2.5 Flash Image ("Nano Banana"), tier gratis de
    # Google AI Studio. Clave server-side only, nunca se expone al frontend.
    gemini_api_key: str = ""
    gemini_image_model: str = "gemini-2.5-flash-image"

    # Orígenes permitidos por CORS, separados por coma. En local alcanza con el
    # frontend de Docker/ng serve; en producción se agrega la URL de Vercel.
    cors_origins: str = "http://localhost:4200"

    model_config = SettingsConfigDict(env_file=(".env", "backend/.env", "../backend/.env"), extra="ignore")

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


settings = Settings()
