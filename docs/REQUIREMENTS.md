# Workflow Engine — Requirements

## Purpose

A standalone, multi-tenant **workflow automation platform** (an n8n-equivalent):
users compose workflows from trigger + action nodes, and the engine executes them
durably, records every run, and supports human-in-the-loop approvals and agentic
AI steps.

## Scope

### In scope

1. **Workflows** — CRUD over node/edge definitions (`/workflows`), with
   versioning, import/export, sharing, and per-workflow trigger config.
2. **Triggers** — webhook, schedule, manual, and event triggers.
3. **Durable execution** — each run is a Temporal workflow with retries and
   idempotency; runs and per-node steps are recorded (`/executions`).
4. **Approvals** — human-in-the-loop approve/reject gates on nodes.
5. **Node palette** — a registry (`/node-types/registry`) of built-in node types
   plus pack-contributed triggers/actions carrying JSON-Schema config.
6. **Rules & forms** — a rules engine and form builder integrated with workflows
   (see the user-guide docs).
7. **AI nodes** — LLM agent steps via smart-llm (multi-provider, key store,
   budgets).
8. **Integrations** — a catalogue of external-service connectors
   (`/integrations/catalogue`: HTTP, Claude, OpenAI, Slack, Gmail, Outlook,
   Stripe, S3, and 20+ more) that tenants configure as named integration
   instances (`/integrations`) backed by stored credentials (`/credentials`) or
   the OAuth2 consent flow (`/oauth2`), managed from the admin UIs' Integrations
   page.
9. **Security** — SSRF egress guard, HMAC-signed webhooks, per-IP rate limiting,
   security headers, field encryption.
10. **Admin UIs** — a Flutter package (full builder canvas + monitor +
    integrations) and a React admin (workflows / executions / forms / node
    palette / integrations).
11. **Operability** — health/readiness, structured logs, Prometheus metrics,
    OpenTelemetry traces (opt-in).

### Out of scope

- The SentinelBuild platform **authorization service** — replaced by a pluggable,
  permissive-default hook (`shared._platform.authz`).
- The **page/web builder host app** — the renderer is vendored into the Flutter
  package (`vendor/web_builder_renderer`) for the embedded form builder only.
- A bundled multi-service reverse-proxy deployment (the compose file runs the
  engine + its dependencies; UIs run separately).

## Functional acceptance criteria

- Creating a workflow and triggering it (`POST /workflows/{id}/execute`) produces
  an execution recorded in `/executions` that reaches a terminal status.
- A workflow's per-node steps are visible via `/executions/{id}/nodes`.
- An inactive workflow is not triggered by its configured trigger.
- Outbound HTTP from action nodes is SSRF-guarded; webhooks are HMAC-signed.
- `GET /integrations/catalogue` lists the available connector types; creating an
  integration (`POST /integrations`) then deleting it (`DELETE
  /integrations/{id}`) round-trips, and the instance is visible via
  `GET /integrations` in between.
- `alembic upgrade head` on an empty database creates every table.

## Non-functional requirements

- **Python** ≥ 3.12; **strict typing** (mypy strict on `api`/`temporal`/`shared`).
- **Lint/format** clean on the blocking ruff gate; CI enforces both.
- **Tests** run with a mocked database (no live Postgres/Temporal required);
  coverage floor enforced (`--cov-fail-under`).
- **Dependency-clean**: no imports of any private host package; `smart-llm` is the
  only first-party dependency, consumed from its public repo.
- **Deployable** as two images (API + Temporal worker) from `backend/`.
