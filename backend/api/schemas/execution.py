import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel


class NodeExecutionResponse(BaseModel):
    id: uuid.UUID
    execution_id: uuid.UUID
    node_id: str
    node_type: str
    status: str
    input_data: dict[str, Any]
    output_data: dict[str, Any]
    error_message: str | None
    started_at: datetime | None
    completed_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}


class ExecutionResponse(BaseModel):
    id: uuid.UUID
    workflow_id: uuid.UUID
    org_id: uuid.UUID
    version_id: uuid.UUID | None = None
    temporal_workflow_id: str | None
    status: str
    input_data: dict[str, Any]
    output_data: dict[str, Any]
    error_message: str | None
    trigger_type: str
    started_at: datetime | None
    completed_at: datetime | None
    created_at: datetime
    # Approval flow
    approval_status: str | None = None
    approval_node_id: str | None = None
    approved_by: str | None = None
    approval_note: str | None = None
    approval_expires_at: datetime | None = None
    # Denormalised — populated by the list endpoint via join
    workflow_name: str | None = None

    model_config = {"from_attributes": True}


class ApprovalActionRequest(BaseModel):
    """Sent when an approver clicks Approve or Reject."""

    action: Literal["approve", "approved", "reject", "rejected"]
    approved_by: str = ""  # Name or email of approver
    note: str = ""  # Optional reason / note
