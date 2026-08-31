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
    ai_api_key: str = ""

    model_config = SettingsConfigDict(env_file=(".env", "backend/.env", "../backend/.env"), extra="ignore")


settings = Settings()
