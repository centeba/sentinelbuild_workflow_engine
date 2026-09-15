"""One-shot migration: rewrite legacy ``claude_llm`` nodes to ``agent_node``.

Phase B / D follow-up. The workflow palette no longer offers
``claude_llm``, and the Temporal worker stopped registering its
activity. Any pre-existing workflow JSON that still references
``claude_llm`` would fail at execution. This script:

1. Walks every ``Workflow.definition`` and ``WorkflowVersion.definition``
   for the org (or all orgs).
2. For each ``claude_llm`` node found, upserts an
   :class:`AIAgentConfig` row labelled
   ``Legacy: <workflow_name>#<node_id>`` carrying the original
   ``system_prompt`` / ``model`` / ``provider_type``.
3. Rewrites the node ``type`` to ``agent_node`` with config
   ``{"agent_id": "<uuid>", "input": "<original prompt>"}``.

Idempotent: re-running on a converted workflow reports 0 changes
because no ``claude_llm`` nodes remain. Run via:

    python -m migrations.agentify_workflows --dry-run
    python -m migrations.agentify_workflows

The ``--archive-stale`` flag (Phase D cleanup) flips ``is_active``
to ``False`` on every "Legacy: …" agent whose source workflow has
been deleted (workflow_id no longer exists). Run monthly via cron.
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys
import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

# integration-hub-owned tables, read via the smart-llm shim that's
# also wired into mit-stack's API layer.
from api.models.ai_agent import AIAgentConfig  # type: ignore[attr-defined]
from api.models.workflow import Workflow
from api.models.workflow_version import WorkflowVersion

# Host imports — run from the mit-stack/backend root so PYTHONPATH
# already has ``api`` and ``shared`` on it.
from shared.db import AsyncSessionLocal

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("agentify")


def _legacy_label(workflow_name: str, node_id: str) -> str:
    return f"Legacy: {workflow_name}#{node_id}"


async def _upsert_legacy_agent(
    session,
    *,
    org_id: uuid.UUID,
    workflow_name: str,
    node_id: str,
    config: dict[str, Any],
) -> uuid.UUID:
    """Find or create the AIAgentConfig that wraps this legacy node.

    Matched by ``(company_id, label)`` — no unique constraint exists,
    so we read first then insert if missing. Two parallel runs of
    this script could race; that's fine, the second insert just
    creates a duplicate row that the next run will pick up.
    """
    label = _legacy_label(workflow_name, node_id)
    name = label.lower().replace(" ", "_").replace(":", "").replace("#", "_")

    existing = (
        (
            await session.execute(
                select(AIAgentConfig).where(
                    AIAgentConfig.company_id == org_id,
                    AIAgentConfig.label == label,
                )
            )
        )
        .scalars()
        .first()
    )
    if existing:
        return existing.id

    row = AIAgentConfig(
        id=uuid.uuid4(),
        company_id=org_id,
        name=name[:255],
        label=label,
        provider_type=(config.get("provider_type") or "anthropic").lower(),
        model_name=config.get("model") or "claude-sonnet-4-6",
        system_prompt=config.get("system_prompt") or "",
        is_active=True,
    )
    session.add(row)
    await session.flush()
    log.info("  + created AIAgentConfig %s (%s)", row.id, label)
    return row.id


def _convert_definition(
    definition: dict[str, Any],
    *,
    workflow_name: str,
    on_legacy_node,  # async callable: (node_id, config) -> agent_id
) -> tuple[dict[str, Any], int]:
    """Return (mutated_definition, number_of_nodes_converted).

    Pure data transform; defers DB writes to ``on_legacy_node`` so
    the caller can decide on dry-run behaviour.
    """
    nodes = list(definition.get("nodes", []))
    converted = 0
    new_nodes: list[dict[str, Any]] = []
    for node in nodes:
        if node.get("type") != "claude_llm":
            new_nodes.append(node)
            continue
        node_id = str(node.get("id", uuid.uuid4()))
        cfg = dict(node.get("config", {}))
        agent_id = on_legacy_node(node_id, cfg)
        new_node = {
            **node,
            "type": "agent_node",
            "config": {
                "agent_id": str(agent_id),
                "input": cfg.get("prompt") or cfg.get("input") or "",
            },
        }
        new_nodes.append(new_node)
        converted += 1
    if converted == 0:
        return definition, 0
    return {**definition, "nodes": new_nodes}, converted


async def agentify(*, dry_run: bool, org_id: uuid.UUID | None = None) -> int:
    """Walk Workflow + WorkflowVersion rows and convert legacy nodes."""
    total_converted = 0
    async with AsyncSessionLocal() as session:
        wf_stmt = select(Workflow)
        if org_id:
            wf_stmt = wf_stmt.where(Workflow.org_id == org_id)
        workflows = (await session.execute(wf_stmt)).scalars().all()

        for wf in workflows:
            pending: list[tuple[str, dict[str, Any]]] = []  # (node_id, config)

            def _enqueue(node_id: str, cfg: dict[str, Any]) -> uuid.UUID:
                # Defer real upsert until after the dict mutation so
                # we don't hold the session open across an async
                # callable inside a sync transformer.
                placeholder = uuid.uuid4()
                pending.append((node_id, cfg, placeholder))
                return placeholder

            new_def, n = _convert_definition(
                wf.definition or {},
                workflow_name=wf.name,
                on_legacy_node=_enqueue,
            )
            if n == 0:
                continue

            log.info("workflow %s (%s): %d legacy node(s)", wf.id, wf.name, n)

            # Resolve placeholders to real agent IDs by upserting now.
            id_map: dict[uuid.UUID, uuid.UUID] = {}
            for node_id, cfg, placeholder in pending:
                real_id = await _upsert_legacy_agent(
                    session,
                    org_id=wf.org_id,
                    workflow_name=wf.name,
                    node_id=node_id,
                    config=cfg,
                )
                id_map[placeholder] = real_id

            # Rewrite the placeholders in-place
            for node in new_def["nodes"]:
                if node.get("type") != "agent_node":
                    continue
                aid = node["config"].get("agent_id")
                try:
                    aid_uuid = uuid.UUID(str(aid))
                except Exception:
                    continue
                if aid_uuid in id_map:
                    node["config"]["agent_id"] = str(id_map[aid_uuid])

            if dry_run:
                log.info("  (dry-run) would update workflow.definition")
            else:
                wf.definition = new_def
                flag_modified(wf, "definition")
            total_converted += n

        # WorkflowVersion snapshots — same pass, but versions are
        # immutable in the product UI; we only rewrite if the version
        # is still the active one (running workflow). Archived /
        # historic versions are left as-is for the audit trail.
        ver_stmt = select(WorkflowVersion).where(WorkflowVersion.status == "active")
        if org_id:
            ver_stmt = ver_stmt.where(WorkflowVersion.org_id == org_id)
        versions = (await session.execute(ver_stmt)).scalars().all()
        for v in versions:
            wf_name = "version"
            wf_row = (
                (
                    await session.execute(
                        select(Workflow).where(Workflow.id == v.workflow_id)
                    )
                )
                .scalars()
                .first()
            )
            if wf_row:
                wf_name = wf_row.name

            pending = []  # type: ignore[assignment]

            def _enqueue_v(node_id: str, cfg: dict[str, Any]) -> uuid.UUID:
                placeholder = uuid.uuid4()
                pending.append((node_id, cfg, placeholder))
                return placeholder

            new_def, n = _convert_definition(
                v.definition or {},
                workflow_name=wf_name,
                on_legacy_node=_enqueue_v,
            )
            if n == 0:
                continue
            log.info("workflow_version %s: %d legacy node(s)", v.id, n)

            id_map = {}
            for node_id, cfg, placeholder in pending:
                real_id = await _upsert_legacy_agent(
                    session,
                    org_id=v.org_id,
                    workflow_name=wf_name,
                    node_id=node_id,
                    config=cfg,
                )
                id_map[placeholder] = real_id

            for node in new_def["nodes"]:
                if node.get("type") != "agent_node":
                    continue
                aid = node["config"].get("agent_id")
                try:
                    aid_uuid = uuid.UUID(str(aid))
                except Exception:
                    continue
                if aid_uuid in id_map:
                    node["config"]["agent_id"] = str(id_map[aid_uuid])

            if dry_run:
                log.info("  (dry-run) would update version.definition")
            else:
                v.definition = new_def
                flag_modified(v, "definition")
            total_converted += n

        if not dry_run:
            await session.commit()
    return total_converted


async def archive_stale() -> int:
    """Phase-D cleanup: deactivate Legacy agents with no live workflow.

    A Legacy agent is "stale" when no workflow's definition references
    its id anymore — typically because the source workflow was
    deleted. Cron this monthly so the AI admin doesn't drown in
    abandoned auto-created entries.
    """
    archived = 0
    async with AsyncSessionLocal() as session:
        # Build set of agent_ids referenced by any current workflow.
        referenced: set[str] = set()
        wf_rows = (await session.execute(select(Workflow))).scalars().all()
        for wf in wf_rows:
            for node in (wf.definition or {}).get("nodes", []):
                if node.get("type") == "agent_node":
                    aid = (node.get("config") or {}).get("agent_id")
                    if aid:
                        referenced.add(str(aid))

        legacy_rows = (
            (
                await session.execute(
                    select(AIAgentConfig).where(
                        AIAgentConfig.label.ilike("Legacy: %"),
                        AIAgentConfig.is_active.is_(True),
                    )
                )
            )
            .scalars()
            .all()
        )
        for agent in legacy_rows:
            if str(agent.id) not in referenced:
                agent.is_active = False
                archived += 1
                log.info("- archived stale legacy agent %s (%s)", agent.id, agent.label)
        await session.commit()
    return archived


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dry-run", action="store_true", help="Don't commit changes")
    p.add_argument(
        "--org-id",
        help="Restrict to a single organization (UUID); default: all orgs",
    )
    p.add_argument(
        "--archive-stale",
        action="store_true",
        help="Mark Legacy AIAgentConfig rows inactive when no workflow "
        "references them (instead of running the conversion pass).",
    )
    args = p.parse_args()

    if args.archive_stale:
        n = asyncio.run(archive_stale())
        log.info("archived %d stale Legacy agent(s)", n)
        return 0

    org = uuid.UUID(args.org_id) if args.org_id else None
    n = asyncio.run(agentify(dry_run=args.dry_run, org_id=org))
    log.info(
        "%s%d legacy claude_llm node(s) processed", "(dry) " if args.dry_run else "", n
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
