"""Pack-action dispatcher activity.

Pack-contributed action nodes (`pack_action`) declare their runtime
endpoint via the manifest's :class:`WorkflowActionSpec` and persist
to the ``pack_node_types`` table. At execution time the workflow
executor calls this activity with the node's `node_key` + resolved
config — the activity looks up the spec, builds the URL
(``{PACK_ROUTER_BASE}/api/{pack_name}/v1{endpoint_path}``), and
POSTs the config as the body.

The pack router base URL is configurable via ``PACK_ROUTER_BASE_URL``
env so deployments where packs run on a separate host (e.g.
restoration-api at :8010) can override the default of "same host as
mit-stack-api". The platform's M2M secret is forwarded as
``X-Internal-Key`` so the pack-owned endpoint can authorise the call
without a user JWT.

Returns the parsed JSON response body so downstream nodes can
reference ``{{nodes.<id>.response.*}}`` in their templates.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from temporalio import activity
from temporalio.exceptions import ApplicationError

from api.models.pack_node_type import PackNodeType
from shared.config import get_settings


@dataclass
class PackActionParams:
    node_key: str
    config: dict[str, Any]
    org_id: str | None = None


@activity.defn
async def dispatch_pack_action(params: PackActionParams) -> dict[str, Any]:
    """Resolve a pack_action node's spec and call its endpoint.

    Raises ApplicationError when the node_key isn't found or the
    pack endpoint returns 5xx — both are fatal-to-execution because
    the workflow can't proceed without the action having effect.
    Non-2xx but <500 surfaces the body in the result so workflow
    branches like ``if_condition`` can react.
    """
    settings = get_settings()
    # Build a fresh engine here rather than reusing the shared one
    # because Temporal worker processes are isolated from the FastAPI
    # connection pool — and re-using the FastAPI session_factory
    # would create cross-process pool contention.
    engine = create_async_engine(settings.database_url)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with session_factory() as db:
        row = (
            (
                await db.execute(
                    select(PackNodeType).where(
                        PackNodeType.kind == "action",
                        PackNodeType.key == params.node_key,
                    )
                )
            )
            .scalars()
            .first()
        )
        if row is None:
            await engine.dispose()
            raise ApplicationError(
                f"Unknown pack action key {params.node_key!r}",
                type="UnknownPackAction",
            )
        pack_name = row.pack_name
        spec = row.manifest_json
    await engine.dispose()

    method = (spec.get("endpoint_method") or "POST").upper()
    endpoint_path = spec.get("endpoint_path") or ""
    if not endpoint_path:
        raise ApplicationError(
            f"Pack action {params.node_key!r} has no endpoint_path",
            type="MisconfiguredPackAction",
        )

    base = os.environ.get("PACK_ROUTER_BASE_URL", "").rstrip("/")
    if not base:
        # Default: same host the FastAPI server is on. Inside the
        # Mit Stack worker container this is the gateway / nginx
        # alias for the pack-owning service.
        base = "http://localhost:8000"
    url = f"{base}/api/{pack_name}/v1{endpoint_path}"

    # Body = the node's config minus node_key (which only identifies
    # which spec to dispatch). Plus org_id so the pack endpoint can
    # scope the call to the right company.
    body: dict[str, Any] = {k: v for k, v in params.config.items() if k != "node_key"}
    if params.org_id:
        body.setdefault("org_id", params.org_id)

    headers = {
        "Content-Type": "application/json",
    }
    internal_key = settings.internal_api_key
    if internal_key:
        headers["X-Internal-Key"] = internal_key

    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.request(method, url, json=body, headers=headers)
        if r.status_code >= 500:
            raise ApplicationError(
                f"Pack action {params.node_key} returned {r.status_code}: "
                f"{r.text[:300]}",
                type="PackActionUpstream5xx",
            )
        try:
            data = r.json()
        except Exception:
            data = {"raw": r.text}
        return {
            "status": r.status_code,
            "body": data,
        }
