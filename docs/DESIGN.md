# Workflow Engine — Design

## Overview

The engine is a FastAPI **API** that stores workflow definitions and dispatches
runs to a **Temporal worker** that executes the node graph durably. State lives
in **Postgres**; **Redis** backs caching, idempotency, and rate limiting.

```
  client ──POST /workflows/{id}/execute──▶  API (uvicorn, :8000)
                                              │  start Temporal workflow
                                              ▼
                                        Temporal server
                                              │
                                              ▼
                                     Temporal worker  (python -m temporal.worker)
                                        run node graph: triggers → actions →
                                        conditionals → AI agent nodes → approvals
                                              │
                                              ▼
                                   executions + node steps (Postgres)
                                              ▲
                        GET /executions, /executions/{id}/nodes, WS /ws/executions/{id}
```

## Backend layout (`backend/`)

- **`api/`** — routers (`workflows`, `executions`, `node_types`, `rules`,
  `rule_flows`, `integrations`, `credentials`, `oauth2`, `auth`, `scraper`),
  Pydantic `schemas`, ORM `models`, `services`, and `deps`.
- **`temporal/`** — `client`, `worker`, `workflows/` (notification/rule/
  execution flows), and `activities/`.
- **`shared/`** — config, db, redis, encryption, ssrf, and the vendored
  **`_platform/`** package (see Decoupling).
- **`alembic/`** — migrations (source of truth for schema).

## Workflow definitions

A workflow's `definition` is a graph: `{ "nodes": [...], "edges": [...] }`. Node
types come from the registry (`/node-types/registry`): built-in groups + types,
plus pack-contributed triggers/actions that ship JSON-Schema config so the
builder renders forms with zero hard-coded fields.

## Execution & approvals

`POST /workflows/{id}/execute` starts a Temporal workflow; the worker walks the
graph, recording an `execution` and per-node `node_execution` rows. Human-in-the-
loop nodes pause with an `approval_status` until `POST /executions/{id}/approve`.
Clients can stream live progress over `WS /ws/executions/{id}`.

## AI nodes (smart-llm)

Agent nodes use the standalone **smart-llm** package: `Agent`/`AgentManager`, the
`DatabaseKeyStore`, provider policy, and usage/budgets. The cross-service budget
gate is the vendored `SmartLlmInvokeClient` (`shared._platform`).

## Safety & hardening

- **SSRF egress guard** (`shared/ssrf.py` → `shared._platform.ssrf`) validates
  outbound URLs and pins resolved IPs, refusing private/loopback/metadata targets.
- **Signed webhooks** — HMAC signing/verification for inbound/outbound webhooks.
- **Rate limiting** — optional per-IP limiter (`shared._platform.rate_limit`),
  no-op unless `RATE_LIMIT_REDIS_URL` is set.
- **Security headers** — `shared._platform.security_headers`.
- **Authorization hook** — `shared._platform.authz.authz_check` defaults to
  permissive standalone; register a real checker via `set_authz_checker`.
- **Scripted rules** run under RestrictedPython / a sandboxed JS engine.

## Decoupling from SentinelBuild

Extracted from the monorepo and made dependency-clean:

| Original coupling | Standalone treatment |
|---|---|
| `smart_llm` | **External dependency** — public `smart-llm`, pinned by git ref |
| `sentinelbuild_sdk` (ssrf, http, config, errors, rate_limit, security_headers, `SmartLlmInvokeClient`) | **Vendored** into `shared/_platform/` (self-contained; imports rehomed) |
| `sentinelbuild_sdk.authz` | **Pluggable hook** — permissive default (`shared._platform.authz`) |
| Flutter siblings (`sentinel_branding`, `lucide_icons`, `web_builder_renderer`, `multi_lang_sdk`) | **Vendored** under `flutter_package/vendor/` |

## Observability

`smart_llm.observability.install_observability` + `smart_llm.logging_config`
provide Prometheus `/metrics`, OpenTelemetry traces, Sentry, and JSON logs — all
activated only when their env is set. Liveness `/health`; deep readiness
`/healthz`.

## Updating smart-llm

The AI layer is pinned by commit in `backend/requirements.txt` and
`backend/pyproject.toml`:

```
smart-llm[db,observability] @ git+https://github.com/centeba/smart-llm@<commit>
```

Bump `<commit>` to a newer `main` SHA (or tag) and re-run the test suite. Pinning
to a SHA keeps builds reproducible.

## Deployment

`backend/Dockerfile.api` and `backend/Dockerfile.worker` each build from the
`backend/` context (smart-llm pulled from git). `docker-compose.yml` runs the full
local stack (postgres, redis, temporal, temporal-ui, api, worker). On Railway, set
each service's root directory to `backend` and use `railway.json` /
`railway.worker.json`.
