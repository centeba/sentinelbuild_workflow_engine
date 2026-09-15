"""Domain-condition evaluation activity.

Backs the ``domain_condition`` branch node: fetch each live domain entity the
condition references (via the pack's ``/actions/query`` read endpoint declared in
its data_domains schema), then evaluate the structured group with
``domain_condition.evaluate_group`` (which reuses the rule engine's operator
logic). Returns a single bool the executor routes to true_branch / false_branch.

Fetching reuses the same plumbing as ``dispatch_pack_action``: the pack-router
base URL + the platform ``X-Internal-Key`` M2M secret, so no auth/URL logic is
re-implemented. ``project_id`` and ``org_id`` come from the workflow context,
never the client.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from temporalio import activity

from api.models.pack_node_type import PackNodeType
from api.services.domain_condition import evaluate_group, referenced_entities
from shared.config import get_settings


@dataclass
class DomainConditionParams:
    conditions: dict[str, Any] = field(default_factory=dict)
    project_id: str = ""
    org_id: str | None = None


@activity.defn
async def evaluate_domain_condition(params: DomainConditionParams) -> bool:
    group = params.conditions or {}
    ents = referenced_entities(group)
    if not ents:
        return True  # no leaves → no restriction
    if not params.project_id:
        # Can't fetch entities without a project id → conditions can't be met.
        return False

    settings = get_settings()

    # Build {entity_key: (pack_name, read)} from every installed pack's
    # data_domain schema. One query; isolated engine (worker ≠ FastAPI pool).
    engine = create_async_engine(settings.database_url)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    read_map: dict[str, tuple[str, dict[str, Any]]] = {}
    async with session_factory() as db:
        rows = (
            (
                await db.execute(
                    select(PackNodeType).where(PackNodeType.kind == "data_domain")
                )
            )
            .scalars()
            .all()
        )
        for row in rows:
            for e in (row.manifest_json or {}).get("entities", []) or []:
                read_map[str(e.get("key"))] = (row.pack_name, e.get("read") or {})
    await engine.dispose()

    base = (
        os.environ.get("PACK_ROUTER_BASE_URL", "").rstrip("/")
        or "http://localhost:8000"
    )
    internal_key = settings.internal_api_key
    headers = {"Content-Type": "application/json"}
    if internal_key:
        headers["X-Internal-Key"] = internal_key

    fetched: dict[str, Any] = {}
    async with httpx.AsyncClient(timeout=20.0) as client:
        for ekey in ents:
            pack_name, read = read_map.get(ekey, (None, {}))
            if not pack_name or not read:
                continue  # unknown entity → leaf evaluates against empty (false)
            endpoint = read.get("endpoint") or "/actions/query"
            query_entity = read.get("entity") or ekey
            url = f"{base}/api/{pack_name}/v1{endpoint}"
            body: dict[str, Any] = {
                "entity": query_entity,
                "project_id": params.project_id,
            }
            if params.org_id:
                body["org_id"] = params.org_id
            try:
                r = await client.post(url, json=body, headers=headers)
                if r.status_code < 400:
                    payload = r.json()
                    fetched[ekey] = (payload.get("data") or {}).get("result")
            except Exception:
                # Best-effort: a fetch failure leaves the entity absent, so its
                # leaves evaluate against empty rather than crashing the branch.
                pass

    return evaluate_group(group, fetched)
