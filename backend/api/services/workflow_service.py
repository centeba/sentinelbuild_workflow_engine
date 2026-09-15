import secrets
import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from temporalio.client import Client

from api.models.execution import WorkflowExecution
from api.models.workflow import Workflow
from shared.config import get_settings
from shared.redis_client import RedisKeys, get_redis

settings = get_settings()


async def get_temporal_client() -> Client:
    from shared.temporal_client import get_temporal_client as _get_temporal_client

    return await _get_temporal_client()


async def _check_trigger_conflict(
    db: AsyncSession,
    org_id: uuid.UUID,
    trigger_type: str,
    scope: str,
    exclude_id: uuid.UUID | None = None,
) -> None:
    """Raise ValueError if a mandated workflow at a higher scope already owns this trigger_type."""
    if scope == "system":
        # system_admin can override anything — no conflict check needed
        return

    q = select(Workflow).where(
        Workflow.trigger_type == trigger_type,
        Workflow.is_mandated == True,  # noqa: E712
    )
    if scope == "personal":
        # personal must not conflict with system OR company mandated workflows for this org
        q = q.where(
            (Workflow.scope == "system")
            | ((Workflow.scope == "company") & (Workflow.org_id == org_id))
        )
    elif scope == "company":
        # company must not conflict with system mandated workflows
        q = q.where(Workflow.scope == "system")

    if exclude_id:
        q = q.where(Workflow.id != exclude_id)

    result = await db.execute(q)
    conflict = result.scalars().first()
    if conflict:
        raise ValueError(
            f"Trigger type '{trigger_type}' is already claimed by a mandated "
            f"'{conflict.scope}' workflow ('{conflict.name}'). "
            f"A '{scope}' workflow cannot use the same trigger."
        )


async def create_workflow(
    db: AsyncSession,
    org_id: uuid.UUID,
    user_id: uuid.UUID,
    name: str,
    description: str | None,
    definition: dict[str, Any],
    trigger_type: str,
    trigger_config: dict[str, Any],
    scope: str = "personal",
    visibility: str = "private",
    is_mandated: bool = False,
    shared_with: list[Any] | None = None,
    owner_org_id: uuid.UUID | None = None,
    source_app: str | None = None,
    office_id: uuid.UUID | None = None,
) -> Workflow:
    await _check_trigger_conflict(db, org_id, trigger_type, scope)

    wf = Workflow(
        org_id=org_id,
        created_by=user_id,
        name=name,
        description=description,
        definition=definition,
        trigger_type=trigger_type,
        trigger_config=trigger_config,
        webhook_secret=secrets.token_hex(32) if trigger_type == "webhook" else None,
        scope=scope,
        visibility=visibility,
        is_mandated=is_mandated,
        shared_with=shared_with or [],
        owner_org_id=owner_org_id,
        source_app=source_app,
        office_id=office_id,
    )
    db.add(wf)
    await db.flush()
    return wf


async def trigger_workflow(
    db: AsyncSession,
    workflow: Workflow,
    input_data: dict[str, Any],
    trigger_type: str = "manual",
    version_id: uuid.UUID | None = None,
) -> WorkflowExecution:
    from temporal.workflows.workflow_executor import (
        WorkflowExecutor,
        WorkflowExecutorParams,
    )

    execution = WorkflowExecution(
        workflow_id=workflow.id,
        org_id=workflow.org_id,
        version_id=version_id,
        status="pending",
        input_data=input_data,
        trigger_type=trigger_type,
    )
    db.add(execution)
    await db.flush()

    # Start Temporal workflow
    temporal_id = f"wf-{workflow.id}-{execution.id}"
    client = await get_temporal_client()
    handle = await client.start_workflow(
        WorkflowExecutor.run,
        WorkflowExecutorParams(
            execution_id=str(execution.id),
            workflow_id=str(workflow.id),
            org_id=str(workflow.org_id),
            input_data=input_data,
            version_id=str(version_id) if version_id else None,
        ),
        id=temporal_id,
        task_queue=settings.temporal_task_queue,
    )
    execution.temporal_workflow_id = temporal_id
    execution.status = "running"
    await db.flush()

    # Cache status in Redis
    redis = await get_redis()
    await redis.setex(RedisKeys.exec_status(str(execution.id)), 300, "running")

    return execution


async def get_workflow_cached(
    db: AsyncSession, workflow_id: uuid.UUID, org_id: uuid.UUID
) -> Workflow | None:
    redis = await get_redis()
    cache_key = RedisKeys.workflow(str(workflow_id))
    cached = await redis.get(cache_key)
    if cached:
        return None  # Return None to signal caller to use cached JSON

    result = await db.execute(
        select(Workflow).where(Workflow.id == workflow_id, Workflow.org_id == org_id)
    )
    wf = result.scalar_one_or_none()
    if wf:
        import orjson

        await redis.setex(
            cache_key,
            60,
            orjson.dumps({"id": str(wf.id), "definition": wf.definition}).decode(),
        )
    return wf
