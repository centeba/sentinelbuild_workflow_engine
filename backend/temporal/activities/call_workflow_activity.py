"""
Call Workflow Activity (Gap 8 — Subworkflow / Call Workflow node)

Starts a child workflow execution (creates its own DB record) and waits
for it to complete, returning its output_data.

This activity is intentionally long-running — it blocks until the child
workflow finishes.  Temporal heartbeating ensures it stays alive.
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass
from typing import Any

from temporalio import activity


@dataclass
class CallSubWorkflowParams:
    parent_execution_id: str
    sub_workflow_id: str  # UUID of the Workflow record to run
    org_id: str
    node_id: str  # for unique Temporal workflow ID
    input_data: dict[str, Any]
    timeout_hours: int = 24


@activity.defn
async def call_sub_workflow(params: CallSubWorkflowParams) -> dict[str, Any]:
    """
    1. Create a WorkflowExecution DB record for the child run.
    2. Start the child WorkflowExecutor Temporal workflow.
    3. Wait (with heartbeat) for it to complete.
    4. Return the child's output_data.
    """
    from datetime import timedelta

    from api.models.execution import WorkflowExecution
    from shared.config import get_settings
    from shared.db import AsyncSessionLocal

    settings = get_settings()
    exe_id = uuid.uuid4()

    # Step 1 — Create sub-execution record in DB
    async with AsyncSessionLocal() as session:
        sub_exe = WorkflowExecution(
            id=exe_id,
            workflow_id=uuid.UUID(params.sub_workflow_id),
            org_id=uuid.UUID(params.org_id),
            trigger_type="sub_workflow",
            status="pending",
            input_data=params.input_data,
        )
        session.add(sub_exe)
        await session.commit()

    # Step 2 — Start child workflow via Temporal client
    from shared.temporal_client import get_temporal_client
    from temporal.workflows.workflow_executor import WorkflowExecutorParams

    temporal_client = await get_temporal_client()
    child_wf_id = f"sub-{params.parent_execution_id[:8]}-{params.node_id}"

    handle = await temporal_client.start_workflow(
        "WorkflowExecutor",
        WorkflowExecutorParams(
            execution_id=str(exe_id),
            workflow_id=params.sub_workflow_id,
            org_id=params.org_id,
            input_data=params.input_data,
        ),
        id=child_wf_id,
        task_queue=settings.temporal_task_queue,
        execution_timeout=timedelta(hours=params.timeout_hours),
    )

    # Step 3 — Poll result with heartbeating
    deadline = asyncio.get_event_loop().time() + params.timeout_hours * 3600
    while True:
        activity.heartbeat(
            {"child_wf_id": child_wf_id, "sub_execution_id": str(exe_id)}
        )
        try:
            result = await asyncio.wait_for(handle.result(), timeout=30)
            break
        except TimeoutError:
            if asyncio.get_event_loop().time() > deadline:
                raise TimeoutError(f"Sub-workflow {child_wf_id} timed out")
            continue

    # Step 4 — Return output
    if hasattr(result, "output_data"):
        return result.output_data or {}
    return result if isinstance(result, dict) else {}
