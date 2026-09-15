from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from smart_llm.logging_config import configure_logging

from shared.middleware import RequestLoggingMiddleware

configure_logging(service_name="mit-stack-api")

from api.routers.auth import router as auth_router
from api.routers.credentials import router as credentials_router
from api.routers.executions import router as executions_router
from api.routers.executions import ws_router
from api.routers.forms import router as forms_router
from api.routers.integrations import router as integrations_router
from api.routers.internal import router as internal_router
from api.routers.node_types import router as node_types_router
from api.routers.oauth2 import router as oauth2_router
from api.routers.rule_flows import router as rule_flows_router
from api.routers.rules import router as rules_router
from api.routers.scraper import router as scraper_router
from api.routers.translations import router as translations_router
from api.routers.workflows import router as workflows_router
from api.routers.workflows import webhook_router
from shared.config import get_settings
from shared.db import engine
from shared.redis_client import close_redis

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    yield
    await close_redis()
    await engine.dispose()


app = FastAPI(
    title="Mit Stack API",
    description="n8n-equivalent workflow automation platform",
    version="0.1.0",
    lifespan=lifespan,
)

# Observability — Prometheus /metrics + Sentry + OTEL. Opt-in via env;
# no-op when libs/env aren't present. See smart_llm.observability.
from smart_llm.observability import install_observability  # noqa: E402

install_observability(
    app, service_name="mit-stack-api", environment=settings.environment
)

from shared._platform.rate_limit import install_rate_limit  # noqa: E402

# Gate 7: blanket per-IP rate limit — no-op until RATE_LIMIT_REDIS_URL is set.
install_rate_limit(app, service_name="mit-stack")

app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# Baseline security response headers (nosniff / frame-deny / referrer / HSTS in prod).
from shared._platform.security_headers import SecurityHeadersMiddleware  # noqa: E402

app.add_middleware(SecurityHeadersMiddleware)

# Idempotency (SB-03): uniform Idempotency-Key replay for mutating requests,
# backed by this service's Redis. Inert unless a client sends the header.
from smart_llm.api.middleware import add_idempotency_middleware  # noqa: E402

from shared.redis_client import get_redis  # noqa: E402

add_idempotency_middleware(app, get_redis)

# API routes (all require auth except webhooks + public forms)
app.include_router(auth_router, prefix="/api/v1")
app.include_router(workflows_router, prefix="/api/v1")
app.include_router(forms_router, prefix="/api/v1")
app.include_router(executions_router, prefix="/api/v1")
app.include_router(credentials_router, prefix="/api/v1")
app.include_router(integrations_router, prefix="/api/v1")
app.include_router(rules_router, prefix="/api/v1")
app.include_router(rule_flows_router, prefix="/api/v1")
app.include_router(oauth2_router, prefix="/api/v1")
app.include_router(node_types_router, prefix="/api/v1")
app.include_router(scraper_router, prefix="/api/v1")

# Public routes (no auth)
app.include_router(webhook_router, prefix="/api/v1")
app.include_router(translations_router, prefix="/api/v1")

# Internal service-to-service API (M2M, no user JWT)
app.include_router(internal_router, prefix="/api/v1")

# WebSocket routes
app.include_router(ws_router)


# ── Readiness probe + uniform 500 handler ─────────────────────────────────────
from smart_llm.service_runtime import (  # noqa: E402
    add_readiness_route,
    db_check,
    install_exception_handler,
    redis_check,
    temporal_check,
)

from api.services.workflow_service import get_temporal_client  # noqa: E402
from shared.db import AsyncSessionLocal  # noqa: E402
from shared.redis_client import get_redis  # noqa: E402

install_exception_handler(app, service_name="mit-stack-api")
add_readiness_route(
    app,
    service_name="mit-stack-api",
    checks={
        "db": db_check(AsyncSessionLocal),
        "redis": redis_check(get_redis),
        "temporal": temporal_check(get_temporal_client),
    },
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "version": "0.1.0"}
