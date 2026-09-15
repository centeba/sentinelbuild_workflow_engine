# workflow-engine — React admin

A Vite + React + TypeScript admin UI for the workflow engine, complementing the
Flutter package ([`flutter_package`](../flutter_package)):

- **Workflows** — list definitions, inspect a workflow's nodes/edges and its
  trigger, and execute it on demand.
- **Executions** — every run, with per-node step status, timings, errors, and
  input/output payloads (the execution monitor).
- **Node Types** — the builder palette: built-in node types by group plus pack
  contributions (triggers/actions).

> The full drag-and-drop workflow *builder canvas* lives in the Flutter package;
> this React admin focuses on management and monitoring over the same API.

## Develop

```bash
npm install
npm run dev            # http://localhost:5175
```

Dev requests to `/api` are proxied to the backend. Point the proxy with
`VITE_API_TARGET` (default `http://localhost:8000`):

```bash
VITE_API_TARGET=http://localhost:8000 npm run dev
```

## Configuration

| Env | Default | Effect |
|---|---|---|
| `VITE_API_BASE` | `/api/v1` | API base path the client calls |
| `VITE_API_TARGET` | `http://localhost:8000` | Dev-proxy upstream for `/api` |

Auth: if present, `localStorage["we_token"]` is sent as a bearer token.

## Build

```bash
npm run build         # tsc --noEmit && vite build → dist/
```
