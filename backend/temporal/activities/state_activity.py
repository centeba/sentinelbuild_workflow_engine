"""Activities that update execution state in DB and emit real-time events via Redis."""

import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from temporalio import activity

from shared.db import AsyncSessionLocal
from shared.redis_client import RedisKeys, get_redis


@dataclass
class UpdateExecutionParams:
    execution_id: str
    status: str
    output_data: dict[str, Any] = field(default_factory=dict)
    error_message: str | None = None


@dataclass
class NodeExecutionUpdate:
    execution_id: str
    node_id: str
    node_type: str
    status: str
    input_data: dict[str, Any] = field(default_factory=dict)
    output_data: dict[str, Any] = field(default_factory=dict)
    error_message: str | None = None


@dataclass
class LogEventParams:
    execution_id: str
    node_id: str
    event: str
    data: dict[str, Any] = field(default_factory=dict)


@activity.defn
async def update_execution_status(params: UpdateExecutionParams) -> None:
    import uuid

    from sqlalchemy import update as sql_update

    from api.models.execution import WorkflowExecution

    now = datetime.now(UTC)
    updates: dict[str, Any] = {"status": params.status}
    if params.status in ("running",):
        updates["started_at"] = now
    if params.status in ("completed", "failed", "cancelled"):
        updates["completed_at"] = now
    if params.output_data:
        updates["output_data"] = params.output_data
    if params.error_message:
        updates["error_message"] = params.error_message

    async with AsyncSessionLocal() as db:
        await db.execute(
            sql_update(WorkflowExecution)
            .where(WorkflowExecution.id == uuid.UUID(params.execution_id))
            .values(**updates)
        )
        await db.commit()

    # Update Redis cache
    redis = await get_redis()
    await redis.setex(RedisKeys.exec_status(params.execution_id), 300, params.status)

    # Emit pub/sub event
    await redis.publish(
        RedisKeys.exec_logs(params.execution_id),
        json.dumps(
            {"type": "execution_status", "status": params.status, "ts": now.isoformat()}
        ),
    )


@activity.defn
async def update_node_execution(params: NodeExecutionUpdate) -> None:
    import uuid

    from sqlalchemy import select

    from api.models.execution import NodeExecution

    now = datetime.now(UTC)

    async with AsyncSessionLocal() as db:
        # Upsert node execution record
        result = await db.execute(
            select(NodeExecution).where(
                NodeExecution.execution_id == uuid.UUID(params.execution_id),
                NodeExecution.node_id == params.node_id,
            )
        )
        node_exec = result.scalar_one_or_none()

        if node_exec is None:
            node_exec = NodeExecution(
                execution_id=uuid.UUID(params.execution_id),
                node_id=params.node_id,
                node_type=params.node_type,
                status=params.status,
                input_data=params.input_data,
                output_data=params.output_data,
                error_message=params.error_message,
                started_at=now if params.status == "running" else None,
                completed_at=now
                if params.status in ("completed", "failed", "skipped")
                else None,
            )
            db.add(node_exec)
        else:
            node_exec.status = params.status
            if params.output_data:
                node_exec.output_data = params.output_data
            if params.error_message:
                node_exec.error_message = params.error_message
            if params.status in ("completed", "failed", "skipped"):
                node_exec.completed_at = now

        await db.commit()

    # Emit pub/sub event
    redis = await get_redis()
    await redis.publish(
        RedisKeys.exec_logs(params.execution_id),
        json.dumps(
            {
                "type": "node_update",
                "node_id": params.node_id,
                "node_type": params.node_type,
                "status": params.status,
                "ts": now.isoformat(),
            }
        ),
    )


@activity.defn
async def emit_log_event(params: LogEventParams) -> None:
    import json
    from datetime import datetime

    redis = await get_redis()
    await redis.publish(
        RedisKeys.exec_logs(params.execution_id),
        json.dumps(
            {
                "type": "log",
                "node_id": params.node_id,
                "event": params.event,
                "data": params.data,
                "ts": datetime.now(UTC).isoformat(),
            }
        ),
    )


@activity.defn(name="create_execution_record")
async def create_execution_record(params: dict[str, Any]) -> None:
    """Create a WorkflowExecution row before a child workflow starts."""
    import uuid

    from api.models.execution import WorkflowExecution

    async with AsyncSessionLocal() as db:
        execution = WorkflowExecution(
            id=uuid.UUID(params["execution_id"]),
            workflow_id=uuid.UUID(params["workflow_id"]),
            org_id=uuid.UUID(params["org_id"]),
            temporal_workflow_id=params.get("temporal_workflow_id"),
            status="running",
            input_data=params.get("input_data", {}),
            trigger_type=params.get("trigger_type", "imap_trigger"),
        )
        db.add(execution)
        await db.commit()


@activity.defn(name="load_workflow_definition")
async def load_workflow_definition(params: dict[str, Any]) -> str:
    import json
    import uuid

    from sqlalchemy import select

    from api.models.workflow import Workflow
    from api.models.workflow_version import WorkflowVersion

    version_id = params.get("version_id")

    async with AsyncSessionLocal() as db:
        # Always load the workflow row — it carries the federation governance
        # (participants + action_authz_rules) the executor needs to gate
        # cross-company action dispatch deterministically (A5).
        result = await db.execute(
            select(Workflow).where(
                Workflow.id == uuid.UUID(params["workflow_id"]),
                Workflow.org_id == uuid.UUID(params["org_id"]),
            )
        )
        wf = result.scalar_one_or_none()
        if not wf:
            raise ValueError(f"Workflow {params['workflow_id']} not found")

        # The DAG itself comes from the immutable published snapshot when a
        # version_id is supplied, else the current draft on the workflow row.
        definition = dict(wf.definition or {})
        if version_id:
            vresult = await db.execute(
                select(WorkflowVersion).where(
                    WorkflowVersion.id == uuid.UUID(version_id),
                    WorkflowVersion.org_id == uuid.UUID(params["org_id"]),
                )
            )
            version = vresult.scalar_one_or_none()
            if version:
                definition = dict(version.definition or {})

        # Merge federation governance (workflow-level, not versioned) so the
        # executor sees it regardless of which definition snapshot was used.
        definition.setdefault("participants", getattr(wf, "participants", None) or [])
        definition.setdefault(
            "action_authz_rules", getattr(wf, "action_authz_rules", None) or {}
        )
        return json.dumps(definition)
