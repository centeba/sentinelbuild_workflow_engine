import secrets
from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # ── App ────────────────────────────────────────────────────────────────────
    app_name: str = "Mit Stack"
    environment: str = "development"
    debug: bool = False
    # LOCAL DEV ONLY: when true (and not production), the API skips JWT auth and
    # acts as a seeded "dev" org/user. Lets the token-less Flutter example call
    # the API. Ignored in production. Never enable outside local development.
    dev_auth_bypass: bool = False

    # ── Database ───────────────────────────────────────────────────────────────
    # Set DATABASE_URL in .env for all environments.
    # Default is a local dev database; never use in production without override.
    database_url: str = (
        "postgresql+asyncpg://mitstack:mitstack_secret@localhost:5432/mitstack"
    )
    # Pool budget. Defaults sized for a single replica; for multi-replica
    # deploys reduce ``db_pool_size`` so N replicas × pool_size stays
    # safely under Postgres ``max_connections``. See
    # documents/platform/architecture-overview.md.
    db_pool_size: int = 20
    db_max_overflow: int = 10

    # ── Redis ──────────────────────────────────────────────────────────────────
    # Set REDIS_URL in .env. Default points to local dev Redis.
    redis_url: str = "redis://:redis_secret@localhost:6379/0"

    # ── Temporal ───────────────────────────────────────────────────────────────
    temporal_host: str = "localhost:7233"
    temporal_address: str = "localhost:7233"  # alias used by activities/client
    temporal_namespace: str = "default"
    temporal_task_queue: str = "mitstack-workflows"
    # HA-readiness: bound the worker's in-flight work so N replicas stay within
    # Temporal/DB/LLM budgets instead of each pulling unbounded tasks.
    temporal_worker_concurrency: int = 50  # max_concurrent_activities
    temporal_max_concurrent_workflow_tasks: int = 20
    # Set to point at Temporal Cloud instead of a self-hosted server — the
    # shared get_temporal_client() helper (shared/temporal_client.py)
    # automatically enables TLS whenever this is non-empty (Temporal Cloud's
    # API-key auth requires it). Leave blank for self-hosted Temporal.
    temporal_api_key: str = ""

    # ── Security ───────────────────────────────────────────────────────────────
    # Left blank by default so _check_production_secrets can tell "unset" from
    # "explicitly configured" — filled with a random per-process value for
    # local/dev convenience (see below), but that fallback would silently
    # invalidate every JWT on every restart/replica if it ever ran in
    # production, so production requires an explicit value.
    secret_key: str = ""
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60
    refresh_token_expire_days: int = 30

    # ── User Master integration ────────────────────────────────────────────────
    # Set USER_MASTER_SECRET_KEY to the same SECRET_KEY value configured in
    # User Master. When set, Mit Stack will accept JWTs issued by User Master
    # and auto-provision the corresponding Organisation and User on first use.
    # Leave blank to operate in standalone mode only.
    user_master_secret_key: str = ""
    user_master_algorithm: str = "HS256"

    # When True (default), Mit Stack's own /auth/register and /auth/login
    # endpoints remain active alongside User Master auth. Set to False in
    # production once all users authenticate via User Master.
    standalone_auth: bool = True

    # AES-256-GCM encryption key for credentials (Fernet).
    # Generate with: python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
    # Required in production; features that encrypt credentials are disabled if blank.
    encryption_key: str = ""

    # ── Integration Hub ────────────────────────────────────────────────────────
    # URL and API key for the shared Integration Hub service.
    # Set INTEGRATION_HUB_URL and INTEGRATION_HUB_API_KEY in .env.
    integration_hub_url: str = "http://localhost:8005"
    integration_hub_api_key: str = ""

    # ── Internal service-to-service API ───────────────────────────────────────
    # Static bearer token shared between SentinelBuild services for M2M calls.
    # Must match INTERNAL_API_KEY in the root .env.
    internal_api_key: str = ""

    # Shared secret for M2M calls to integration-hub ``/ai-tools/run``.
    # Must match ``INTERNAL_SERVICE_SECRET`` on the integration-hub container.
    # The Temporal worker sends this as ``Authorization: Bearer <token>``
    # instead of minting a forged system_admin JWT.
    internal_service_secret: str = ""

    # ── External APIs ──────────────────────────────────────────────────────────
    # Anthropic — used by the AI rule builder endpoint; feature disabled if blank.
    anthropic_api_key: str = ""
    # OpenAI — optional fallback for the AI rule builder when Anthropic is unavailable.
    openai_api_key: str = ""

    # ── Rule cache ─────────────────────────────────────────────────────────────
    rule_cache_ttl: int = 300  # seconds

    # ── Public base URL ────────────────────────────────────────────────────────
    # Used in approval email links and OAuth2 redirect URIs.
    public_base_url: str = "http://localhost:8000"

    # ── SMTP (approval emails) ─────────────────────────────────────────────────
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_pass: str = ""
    smtp_from: str = ""

    # ── Google OAuth2 (Gmail / Drive) ──────────────────────────────────────────
    google_oauth_client_id: str = ""
    google_oauth_client_secret: str = ""

    # ── Microsoft OAuth2 (Outlook / OneDrive) ─────────────────────────────────
    microsoft_oauth_client_id: str = ""
    microsoft_oauth_client_secret: str = ""

    # ── CORS ───────────────────────────────────────────────────────────────────
    # Comma-separated list of allowed origins.
    cors_origins: str = "http://localhost:3000"

    # ── JavaScript sandbox ────────────────────────────────────────────────────
    # Hard limit on JS rule execution (dukpy/Duktape). Gap 11.
    js_timeout_ms: int = 2000

    # ── HTTP action timeout ────────────────────────────────────────────────────
    # Timeout in seconds for outbound webhook actions fired by the rule engine.
    webhook_action_timeout_seconds: float = 10.0

    # ── Pagination ────────────────────────────────────────────────────────────
    pagination_default_limit: int = 50
    pagination_max_limit: int = 500

    # ── Computed properties ────────────────────────────────────────────────────

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",")]

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    # ── Production safety guard ────────────────────────────────────────────────

    @model_validator(mode="after")
    def _check_production_secrets(self) -> "Settings":
        """Raise on startup if critical secrets are missing in production."""
        if self.environment != "production":
            # Local/dev convenience: a random key that's stable for the life of
            # this process (regenerating per-request would break sessions
            # immediately) but intentionally NOT persisted anywhere, so it's
            # never mistaken for a real configured secret.
            if not self.secret_key:
                self.secret_key = secrets.token_hex(32)
            return self
        errors: list[str] = []
        if not self.secret_key:
            errors.append(
                "SECRET_KEY must be set in production — left unset, every "
                "restart or replica mints a different key, silently "
                "invalidating all existing JWTs"
            )
        if not self.encryption_key:
            errors.append("ENCRYPTION_KEY must be set in production")
        # Detect hardcoded dev DB credentials — reject in production
        if (
            "mitstack_secret" in self.database_url
            or "mitstack:mitstack" in self.database_url
        ):
            errors.append(
                "DATABASE_URL must not use default dev credentials in production"
            )
        # Detect hardcoded dev Redis credentials
        if "redis_secret" in self.redis_url:
            errors.append(
                "REDIS_URL must not use default dev credentials in production"
            )
        # Require User Master integration in production (standalone_auth should be off)
        if self.standalone_auth:
            errors.append(
                "STANDALONE_AUTH must be False in production; use User Master for auth"
            )
        if not self.smtp_host and self.smtp_from:
            errors.append("SMTP_HOST must be set when SMTP_FROM is configured")
        if self.public_base_url.startswith("http://localhost"):
            errors.append("PUBLIC_BASE_URL must not be localhost in production")
        if errors:
            raise ValueError(
                "Production configuration errors:\n"
                + "\n".join(f"  • {e}" for e in errors)
            )
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
