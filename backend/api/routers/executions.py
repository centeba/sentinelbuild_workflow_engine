import uuid
from collections.abc import Sequence
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user, resolve_user_from_token
from api.models.execution import NodeExecution, WorkflowExecution
from api.schemas.execution import (
    ApprovalActionRequest,
    ExecutionResponse,
    NodeExecutionResponse,
)
from shared.config import get_settings
from shared.db import AsyncSessionLocal, get_db
from shared.redis_client import RedisKeys, get_redis

_s = get_settings()

router = APIRouter(prefix="/executions", tags=["executions"])


@router.get("", response_model=list[ExecutionResponse])
async def list_executions(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(default=_s.pagination_default_limit, le=_s.pagination_max_limit),
    workflow_id: uuid.UUID | None = Query(default=None),
    approval_pending: bool | None = Query(default=None),
) -> list[ExecutionResponse]:
    from sqlalchemy.orm import joinedload

    q = (
        select(WorkflowExecution)
        .options(joinedload(WorkflowExecution.workflow))
        .where(WorkflowExecution.org_id == current.org_id)
    )
    if workflow_id:
        q = q.where(WorkflowExecution.workflow_id == workflow_id)
    if approval_pending is True:
        q = q.where(WorkflowExecution.approval_status == "pending")
    q = q.order_by(WorkflowExecution.created_at.desc()).limit(limit)
    result = await db.execute(q)
    rows = result.unique().scalars().all()
    out: list[ExecutionResponse] = []
    for row in rows:
        d = ExecutionResponse.model_validate(row)
        d.workflow_name = row.workflow.name if row.workflow else None
        out.append(d)
    return out


@router.get("/approval-action")
async def approval_action_link(
    token: str,
    action: str,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> HTMLResponse:
    """
    Public endpoint embedded in approval emails.
    No auth required — the token itself is the credential.
    action: "approve" | "reject"
    """
    result = await db.execute(
        select(WorkflowExecution).where(WorkflowExecution.approval_token == token)
    )
    exe = result.scalar_one_or_none()
    if not exe:
        return HTMLResponse(
            _approval_html("Invalid or expired approval link.", success=False)
        )

    if exe.approval_status != "pending":
        return HTMLResponse(
            _approval_html(
                f"This request has already been {exe.approval_status}.", success=False
            )
        )

    if exe.approval_expires_at and exe.approval_expires_at < datetime.now(UTC):
        return HTMLResponse(
            _approval_html("This approval link has expired.", success=False)
        )

    normalized = "approved" if action in ("approve", "approved") else "rejected"
    await _send_temporal_signal(exe.temporal_workflow_id, normalized, "")

    # Update DB
    exe.approval_status = normalized
    exe.approved_by = "Email link"
    await db.flush()

    verb = "approved" if normalized == "approved" else "rejected"
    return HTMLResponse(
        _approval_html(f"Request {verb}. You may close this tab.", success=True)
    )


@router.get("/{execution_id}", response_model=ExecutionResponse)
async def get_execution(
    execution_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> WorkflowExecution:
    result = await db.execute(
        select(WorkflowExecution).where(
            WorkflowExecution.id == execution_id,
            WorkflowExecution.org_id == current.org_id,
        )
    )
    exe = result.scalar_one_or_none()
    if not exe:
        raise HTTPException(status_code=404, detail="Execution not found")
    return exe


@router.get("/{execution_id}/nodes", response_model=list[NodeExecutionResponse])
async def get_node_executions(
    execution_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Sequence[NodeExecution]:
    exe_result = await db.execute(
        select(WorkflowExecution).where(
            WorkflowExecution.id == execution_id,
            WorkflowExecution.org_id == current.org_id,
        )
    )
    if not exe_result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Execution not found")

    result = await db.execute(
        select(NodeExecution)
        .where(NodeExecution.execution_id == execution_id)
        .order_by(NodeExecution.created_at)
    )
    return result.scalars().all()


# ── Approval endpoints ────────────────────────────────────────────────────────


@router.post("/{execution_id}/approve", response_model=ExecutionResponse)
async def approve_execution(
    execution_id: uuid.UUID,
    body: ApprovalActionRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> WorkflowExecution:
    """
    Approve or reject a paused workflow (from the UI, for authenticated users).
    Sends an `approval_signal` to the Temporal workflow.
    """
    return await _action_approval(
        execution_id=execution_id,
        org_id=current.org_id,
        action=body.action,
        approved_by=body.approved_by or current.email,
        note=body.note,
        db=db,
    )


async def _action_approval(
    execution_id: uuid.UUID,
    org_id: uuid.UUID,
    action: str,
    approved_by: str,
    note: str,
    db: AsyncSession,
) -> WorkflowExecution:
    result = await db.execute(
        select(WorkflowExecution).where(
            WorkflowExecution.id == execution_id,
            WorkflowExecution.org_id == org_id,
        )
    )
    exe = result.scalar_one_or_none()
    if not exe:
        raise HTTPException(status_code=404, detail="Execution not found")
    if exe.approval_status != "pending":
        raise HTTPException(status_code=409, detail=f"Already {exe.approval_status}")

    normalized = "approved" if action in ("approve", "approved") else "rejected"
    await _send_temporal_signal(exe.temporal_workflow_id, normalized, note)

    exe.approval_status = normalized
    exe.approved_by = approved_by
    exe.approval_note = note or None
    await db.flush()
    return exe


class AgentRunApprovalRequest(BaseModel):
    decision: str  # "approve" | "approved" | "reject" | "rejected"


@router.post("/agent-runs/{workflow_id}/approve")
async def approve_agent_run(
    workflow_id: str,
    body: AgentRunApprovalRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, Any]:
    """Approve or reject a paused autonomous-agent run (durable AgentRunWorkflow).
    Signals the workflow by id with the ``approve`` signal so the gated tool
    either dispatches or is rejected."""
    # SEC H3 — authorize before signalling. The agent-run Temporal id is
    # ``agentrun-{execution_id}-{node_id}``; resolve the embedded execution and
    # require it belongs to the caller's org. Previously this signalled any
    # caller-supplied workflow_id with no ownership check, so one tenant could
    # approve/reject another tenant's paused AI run (a UUID is not authz).
    prefix = "agentrun-"
    if not workflow_id.startswith(prefix):
        raise HTTPException(status_code=404, detail="Agent run not found")
    exec_id_str = workflow_id[len(prefix) :][:36]  # str(uuid) is exactly 36 chars
    try:
        exec_uuid = uuid.UUID(exec_id_str)
    except ValueError:
        raise HTTPException(status_code=404, detail="Agent run not found")
    owned = (
        await db.execute(
            select(WorkflowExecution.id).where(
                WorkflowExecution.id == exec_uuid,
                WorkflowExecution.org_id == current.org_id,
            )
        )
    ).scalar_one_or_none()
    if owned is None:
        raise HTTPException(status_code=404, detail="Agent run not found")

    normalized = "approved" if body.decision in ("approve", "approved") else "rejected"
    try:
        from shared.temporal_client import get_temporal_client

        client = await get_temporal_client()
        await client.get_workflow_handle(workflow_id).signal("approve", normalized)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"signal failed: {exc}") from exc
    return {"ok": True, "decision": normalized}


async def _send_temporal_signal(
    temporal_wf_id: str | None, action: str, note: str
) -> None:
    if not temporal_wf_id:
        return
    try:
        from shared.temporal_client import get_temporal_client

        client = await get_temporal_client()
        handle = client.get_workflow_handle(temporal_wf_id)
        # pre-existing bug fixed: passed 2 positional args to the string-name signal overload which takes (signal, arg); the extra arg was dropped/mismatched
        await handle.signal("approval_signal", args=[action, note])
    except Exception as exc:
        import logging

        logging.getLogger(__name__).warning("Failed to send Temporal signal: %s", exc)


def _approval_html(message: str, success: bool) -> str:
    color = "#22C55E" if success else "#EF4444"
    icon = "✓" if success else "✗"
    return f"""<!DOCTYPE html>
<html>
<body style="font-family:-apple-system,sans-serif;background:#0F1117;color:#E2E8F0;
             display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="text-align:center;padding:40px;background:#1A1D2E;border-radius:16px;
              border:1px solid #2D3148;max-width:400px;">
    <div style="font-size:48px;color:{color};margin-bottom:16px;">{icon}</div>
    <p style="font-size:16px;color:#E2E8F0;">{message}</p>
    <button onclick="window.close()"
            style="margin-top:20px;padding:10px 24px;background:{color};color:#fff;
                   border:none;border-radius:8px;cursor:pointer;font-size:14px;">
      Close
    </button>
  </div>
</body>
</html>"""


# ── WebSocket for live log streaming ─────────────────────────────────────────

ws_router = APIRouter(prefix="/ws", tags=["websocket"])


@ws_router.websocket("/executions/{execution_id}")
async def execution_logs_ws(websocket: WebSocket, execution_id: str) -> None:
    """Subscribe to real-time execution log events via Redis Pub/Sub.

    Auth (S2): the channel relays another tenant's live node I/O, HTTP bodies
    and DB rows, so the handshake requires a JWT (sent in the first message —
    browsers can't set WS headers) AND the execution must belong to the
    caller's org. Both checks happen before we subscribe to the Redis channel.
    """
    await websocket.accept()
    try:
        init = await websocket.receive_json()
    except (WebSocketDisconnect, ValueError, Exception):  # noqa: BLE001
        await websocket.close(code=1003)
        return
    token = init.get("token") if isinstance(init, dict) else None

    try:
        exec_uuid = uuid.UUID(execution_id)
    except ValueError:
        await websocket.send_json({"error": "not found"})
        await websocket.close(code=4404)
        return

    async with AsyncSessionLocal() as db:
        current = await resolve_user_from_token(token or "", db)
        if current is None:
            await websocket.send_json({"error": "unauthorized"})
            await websocket.close(code=4401)
            return
        exe = (
            await db.execute(
                select(WorkflowExecution).where(
                    WorkflowExecution.id == exec_uuid,
                    WorkflowExecution.org_id == current.org_id,
                )
            )
        ).scalar_one_or_none()
        if exe is None:
            # Don't distinguish "missing" from "other tenant's" — both 4404.
            await websocket.send_json({"error": "not found"})
            await websocket.close(code=4404)
            return

    redis = await get_redis()
    pubsub = redis.pubsub()
    channel = RedisKeys.exec_logs(execution_id)
    await pubsub.subscribe(channel)
    try:
        async for message in pubsub.listen():
            if message["type"] == "message":
                await websocket.send_text(message["data"])
    except WebSocketDisconnect:
        pass
    finally:
        await pubsub.unsubscribe(channel)
        await pubsub.aclose()  # type: ignore[no-untyped-call]  # redis-py PubSub.aclose is untyped
