from pathlib import Path

from pydantic import Field, HttpUrl, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[1] / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
        hide_input_in_errors=True,
    )

    gemini_api_key: SecretStr = SecretStr("")
    gemini_model: str = ""
    aspnet_api_base_url: HttpUrl = HttpUrl("http://localhost:5000")
    ai_timeout_seconds: float = Field(default=10, gt=0, le=60)
    ai_max_attempts: int = Field(default=2, ge=1, le=3)
    aspnet_timeout_seconds: float = Field(default=10, gt=0, le=60)
    internal_workflow_token: SecretStr = SecretStr("")
    workflow_timeout_seconds: float = Field(default=120, gt=0, le=180)

    @field_validator("aspnet_api_base_url")
    @classmethod
    def backend_origin_only(cls, value):
        if value.username or value.password or value.query or value.fragment or value.path not in (None, "/"):
            raise ValueError("Supply an HTTP(S) backend origin without credentials, path, query or fragment")
        return value

    @field_validator("gemini_api_key", mode="before")
    @classmethod
    def trim_key(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator("gemini_model")
    @classmethod
    def trim_model(cls, value: str) -> str:
        return value.strip()

    @property
    def ai_configured(self) -> bool:
        return bool(self.gemini_api_key.get_secret_value() and self.gemini_model)
