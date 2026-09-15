"""GET /api/v1/node-types — workflow-builder palette registry.

Combines the built-in node types (see
``api/services/node_type_catalog.py``) with every pack-contributed
trigger / action / palette-group spec persisted in the
``pack_node_types`` table.

The workflow builder (frontend/mit_stack) reads this endpoint at
``WorkflowBuilderScreen`` mount time and uses the response to render
both the left-side palette and the right-side schema-driven config
panel — replacing the historical hardcoded `_staticGroups` +
`_fieldsFor()` switch.

No per-org scoping today: pack contributions are process-wide. The
``company_id`` query param is reserved for future opt-in / per-org
overrides (e.g. when only some companies have the restoration pack
permission) but is currently accepted-and-ignored so callers can
start passing it ahead of the toggle landing.
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.pack_node_type import PackNodeType
from api.services.node_type_catalog import BUILTIN_GROUPS, builtin_node_types
from shared.db import get_db

router = APIRouter(prefix="/node-types", tags=["node-types"])


@router.get("/registry")
async def get_registry(
    db: AsyncSession = Depends(get_db),
    company_id: str | None = Query(default=None),  # reserved
    user: CurrentUser = Depends(get_current_user),
) -> dict[str, Any]:
    """Return the merged palette: built-ins + pack contributions.

    Shape::

        {
          "built_in_groups": [...],          # from node_type_catalog.BUILTIN_GROUPS
          "built_in_node_types": [...],      # flat list (key, group_key, kind)
          "pack_groups": [...],              # from pack_node_types where kind=group
          "pack_triggers": [...],            # from pack_node_types where kind=trigger
          "pack_actions": [...],             # from pack_node_types where kind=action
        }

    Pack-contributed entries carry full JSON Schema metadata
    (``payload_schema``, ``filter_schema``, ``config_schema``) so the
    config panel can render forms with zero hard-coded fields.
    """
    _ = company_id  # accepted-and-ignored until per-org opt-in lands

    rows = (await db.execute(select(PackNodeType))).scalars().all()

    pack_triggers: list[dict[str, Any]] = []
    pack_actions: list[dict[str, Any]] = []
    pack_groups: list[dict[str, Any]] = []
    pack_themes: list[dict[str, Any]] = []  # one entry per pack that ships a theme
    pack_data_domains: list[dict[str, Any]] = []  # no-code condition-builder schema
    pack_scraper_connectors: list[dict[str, Any]] = []  # multi-tenant scraper templates
    for row in rows:
        entry = {
            "pack_name": row.pack_name,
            "key": row.key,
            **row.manifest_json,
        }
        if row.kind == "trigger":
            pack_triggers.append(entry)
        elif row.kind == "action":
            pack_actions.append(entry)
        elif row.kind == "group":
            pack_groups.append(entry)
        elif row.kind == "theme":
            pack_themes.append(entry)
        elif row.kind == "data_domain":
            pack_data_domains.append(entry)
        elif row.kind == "scraper_connector":
            pack_scraper_connectors.append(entry)

    return {
        "built_in_groups": BUILTIN_GROUPS,
        "built_in_node_types": builtin_node_types(),
        "pack_groups": pack_groups,
        "pack_triggers": pack_triggers,
        "pack_actions": pack_actions,
        # Pack-declared shell themes (`PackThemeSpec`). When the
        # frontend sees exactly one entry here, it applies that
        # pack's branding to the chassis shell — product name,
        # primary color, logo, default landing route.
        "pack_themes": pack_themes,
        # Per-pack domain-data schema (entities → fields → values) that the
        # no-code condition builder reads to render domain→field→value pickers.
        "pack_data_domains": pack_data_domains,
        # Per-pack authenticated-scraper templates (multi-tenant); each tenant
        # supplies their own credential to instantiate a session.
        "pack_scraper_connectors": pack_scraper_connectors,
    }


@router.get("/{node_key:path}")
async def get_node_type(
    node_key: str,
    db: AsyncSession = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
) -> dict[str, Any]:
    """Return the full spec for a single node type by key.

    The Flutter config panel calls this when the user selects a node
    on the canvas — built-ins return a placeholder (the frontend uses
    its hand-tuned ``_FieldDef`` array) while pack contributions
    return their full JSON Schema for ``SchemaDrivenConfigForm`` to
    render.
    """
    # Built-in lookup first — cheap, in-memory.
    for entry in builtin_node_types():
        if entry["key"] == node_key:
            return entry

    # Pack lookup — trigger and action keys are namespaced
    # (``<pack>.<noun>``), so we don't risk colliding with built-ins.
    row = (
        (await db.execute(select(PackNodeType).where(PackNodeType.key == node_key)))
        .scalars()
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail=f"Unknown node type {node_key!r}")
    return {
        "pack_name": row.pack_name,
        "kind": row.kind,
        "key": row.key,
        **row.manifest_json,
    }
