"""Settings model — reads SENTINELBUILD_* env vars or accepts overrides directly."""

from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class SentinelBuildSettings(BaseSettings):
    """Configuration for the SentinelBuild SDK.

    Vertical apps either let the SDK read from environment (recommended) or
    instantiate this class explicitly with overrides for testing.
    """

    model_config = SettingsConfigDict(
        env_prefix="SENTINELBUILD_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Auth
    shared_secret_key: str = Field(
        default="", description="HS256 secret matching user-master (legacy/fallback)"
    )
    internal_api_key: str = Field(default="", description="M2M bearer token")
    webhook_secret: str = Field(
        default="", description="HMAC secret for webhook signing"
    )
    webhook_replay_redis_url: str = Field(
        default="",
        description=(
            "Redis URL for the webhook replay-nonce store (Gate 7). When set, a "
            "verified webhook's signature is single-use within its freshness "
            "window — a replayed request is rejected. Unset = no replay check."
        ),
    )
    jwt_algorithm: str = Field(default="HS256")
    # RS256 asymmetric verification (preferred). When ``jwt_public_key`` is set,
    # RS256 tokens are verified with it; HS256 tokens still validate against
    # ``shared_secret_key`` during the migration window (dual-mode). ``aud``/
    # ``iss`` are enforced only when configured, so pre-migration HS256 tokens
    # (which carry neither) keep validating. PEM string; supports "\n"-escaped.
    jwt_public_key: str = Field(
        default="", description="RS256 public key (PEM) for verifying user-master JWTs"
    )
    jwt_audience: str = Field(
        default="", description="Expected JWT audience (aud); '' disables the check"
    )
    jwt_issuer: str = Field(
        default="", description="Expected JWT issuer (iss); '' disables the check"
    )
    jwt_jwks_url: str = Field(
        default="",
        description="JWKS URL to fetch RS256 key(s) by kid (supports rotation)",
    )

    # Service URLs (defaults match the Docker Compose service names)
    user_master_url: str = Field(default="http://user-master:8000")
    mit_stack_url: str = Field(default="http://mit-stack:8001")
    doc_vault_url: str = Field(default="http://doc-vault:8002")
    esign_url: str = Field(default="http://esignature:8003")
    integration_hub_url: str = Field(default="http://integration-hub:8005")
    pages_api_url: str = Field(default="http://pages-api:8007")
    smart_llm_url: str = Field(
        default="http://smart-llm:8010"
    )  # if smart-llm is exposed as a service
    authz_url: str = Field(default="http://authz:8000")  # ReBAC authorization service

    # HTTP client behavior
    request_timeout_seconds: float = Field(default=30.0)
    request_max_retries: int = Field(default=3)
    request_backoff_factor: float = Field(default=0.5)

    # Circuit breaker for outbound inter-service calls (BaseHttpClient).
    # Once a downstream host returns `circuit_breaker_failure_threshold` failures
    # (5xx-after-retries or network errors), further calls to it fail fast with a
    # typed 503 (ServiceUnavailableError) for `recovery_timeout` seconds instead of
    # piling retries onto a service that is already down. 4xx responses are healthy
    # and never trip the breaker. Set enabled=False to restore pure retry behavior.
    circuit_breaker_enabled: bool = Field(default=True)
    circuit_breaker_failure_threshold: int = Field(default=5, ge=1)
    circuit_breaker_recovery_timeout: float = Field(default=30.0, gt=0)

    # Webhook policy
    webhook_max_age_seconds: int = Field(
        default=300, description="Reject webhooks older than this (replay protection)"
    )
