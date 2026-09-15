# sentinelbuild-workflow-engine

An **n8n-equivalent workflow automation platform** for Python — a durable
workflow engine with a visual builder, form builder, and execution monitor.
Built on [Temporal](https://temporal.io) for durable orchestration and
[smart-llm](https://github.com/centeba/smart-llm) for its agentic AI nodes.
Standalone and dependency-clean (no host-platform coupling).

## Features

- **Visual workflows** — node/edge definitions with triggers (webhook, schedule,
  manual, event), actions, conditionals, and AI agent nodes.
- **Durable execution** — every run orchestrated by a Temporal workflow with
  retries, approvals (human-in-the-loop), and a queryable execution history.
- **Node palette** — a registry of built-in node types plus pack-contributed
  triggers/actions, each with JSON-Schema config so the builder renders forms
  with no hard-coded fields.
- **Agentic AI nodes** — multi-provider LLM steps via smart-llm (Anthropic /
  OpenAI / Gemini / OpenRouter), with key management and budgets.
- **Integrations** — connectors and OAuth2 flows for external services.
- **Hardened** — SSRF egress guard, HMAC-signed webhooks, per-IP rate limiting,
  security headers, field encryption.
- **Observability** — structured JSON logs, Prometheus `/metrics`, OpenTelemetry
  traces, deep `/healthz` (all opt-in via smart-llm's rails).

## Processes

| Command | Role |
|---|---|
| `uvicorn api.main:app` | Orchestration API (`:8000`) |
| `python -m temporal.worker` | Temporal worker (runs workflow/activity code) |

## Quick start

```bash
docker compose up -d          # postgres + redis + temporal + api + worker
# API at http://localhost:8000 ; Temporal UI at http://localhost:8080
```

Local (backend) without Docker:

```bash
cd backend
python -m venv .venv && . .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"                         # pulls smart-llm from git + deps
cp ../.env.example .env
alembic upgrade head
uvicorn api.main:app --reload                    # + `python -m temporal.worker` in another shell
```

Requires Postgres, Redis, and Temporal — see [`.env.example`](.env.example).

## Admin UIs

Two front-ends over the same API:

- [`flutter_package/`](flutter_package) — the Flutter package (`mit_stack`):
  the full **workflow builder canvas**, form builder, and execution monitor,
  embeddable into any Flutter app.
- [`react-admin/`](react-admin) — a Vite + React + TypeScript admin for
  **workflows, executions, and the node-type palette** (management + monitoring).

## Documentation

- [Requirements](docs/REQUIREMENTS.md) — scope and acceptance criteria.
- [Design](docs/DESIGN.md) — architecture, workflows, safety model, decoupling.
- [Workflows / rules / forms user guide](docs/user-guide-workflows-rules-forms.md).
- [Rules-engine ↔ workflow integration](docs/rules-engine-workflow-integration.md).

## Relationship to smart-llm

The AI layer is **not vendored** — this repo depends on the standalone
[`smart-llm`](https://github.com/centeba/smart-llm) package (pinned by git ref in
`backend/requirements.txt` and `backend/pyproject.toml`). See the design doc's
"Updating smart-llm".

## Layout

- `backend/` — the service (`api`, `temporal`, `shared`, with vendored
  `shared/_platform` platform utilities), Dockerfiles, Alembic migrations.
- `flutter_package/` — the Flutter UI package (with vendored sibling packages
  under `vendor/`).
- `react-admin/` — the React admin.
- `docs/` — design and usage notes.

## License

MIT — see [`LICENSE`](LICENSE).
