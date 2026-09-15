# Package Startup & Configuration Guide

This guide provides the necessary environment variables and startup steps for the core **Mit Stack** engine and its specialized **Integration Hub** connector component.

---

## 1. Mit Stack (Core Orchestrator)

The core engine handles workflows, the rules engine, and overall platform state.

### Environment Variables (.env)

| Variable | Description | Default |
|:---|:---|:---|
| `SECRET_KEY` | JWT signing secret. | `openssl rand -hex 32` |
| `ENCRYPTION_KEY` | Fernet key for credential vault. | `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"` |
| `DATABASE_URL` | Async PostgreSQL DSN. | `postgresql+asyncpg://user:pass@localhost/db` |
| `REDIS_URL` | Async Redis DSN. | `redis://localhost:6379/0` |
| `TEMPORAL_HOST` | Temporal server address. | `localhost:7233` |

### Startup Activities

```bash
# 1. Apply Database Migrations
alembic upgrade head

# 2. Start the API Server
uvicorn api.main:app --host 0.0.0.0 --port 8000

# 3. Start the Temporal Worker
python -m temporal.worker
```

---

## 2. Integration Hub (Connector Service)

The Hub handles browser-based scraping, email/SMS dispatch, and incoming webhooks.

### Environment Variables (.env)

| Variable | Description | Default |
|:---|:---|:---|
| `SECRET_KEY` | JWT signing secret (match Mit Stack). | Same as Core |
| `FIELD_ENCRYPTION_KEY` | AES-256-GCM key for session data. | 32-byte hex string |
| `SQLALCHEMY_DATABASE_URI` | Async PostgreSQL DSN for Hub. | Separate DB recommended |
| `REDIS_URL` | Async Redis DSN for Hub. | Same as Core |
| `TEMPORAL_HOST` | Temporal server address. | Same as Core |
| `INTERNAL_SERVICE_SECRET` | Bearer token for inter-service calls. | Custom string |

### Startup Activities

```bash
# 1. Apply Hub Database Migrations
alembic upgrade head

# 2. Initialize Headless Browser (CRITICAL)
playwright install chromium

# 3. Start the Hub API Server
uvicorn integration_hub_backend.api.main:app --host 0.0.0.0 --port 8001

# 4. Start the Scraper & Notification Worker
python -m integration_hub_backend.api.temporal.worker
```

> [!IMPORTANT]
> The `Mit Stack` must be configured with the `Integration Hub` API URL to delegate certain node types (e.g., Stripe, Hubspot). The Hub worker must be running and listening on the `scraper_queue` to handle `web_scraper` nodes.
