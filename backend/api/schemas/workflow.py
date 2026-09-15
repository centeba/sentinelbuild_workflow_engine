import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel


class WorkflowCreate(BaseModel):
    name: str
    description: str | None = None
    definition: dict[str, Any] = {"nodes": [], "edges": []}
    trigger_type: str = "manual"
    trigger_config: dict[str, Any] = {}
    is_active: bool = True
    # Vertical-app ownership tag. None → generic platform workflow;
    # "restoration" → restoration domain workflow. See list_workflows.
    source_app: str | None = None
    # A5 cross-company federation: participating companies + per-node authz rules.
    participants: list[dict[str, Any]] = []
    action_authz_rules: dict[str, Any] = {}


class WorkflowUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    definition: dict[str, Any] | None = None
    trigger_type: str | None = None
    trigger_config: dict[str, Any] | None = None
    is_active: bool | None = None
    participants: list[dict[str, Any]] | None = None
    action_authz_rules: dict[str, Any] | None = None


class WorkflowResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    description: str | None
    definition: dict[str, Any]
    is_active: bool
    trigger_type: str
    trigger_config: dict[str, Any]
    webhook_secret: str | None
    active_version_id: uuid.UUID | None = None
    source_app: str | None = None
    participants: list[dict[str, Any]] = []
    action_authz_rules: dict[str, Any] = {}
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class TriggerResponse(BaseModel):
    execution_id: uuid.UUID
    temporal_workflow_id: str
    status: str


class TriggerInfoResponse(BaseModel):
    trigger_type: str
    trigger_config: dict[str, Any]
    webhook_url: str | None = None
    webhook_secret: str | None = None


# ── Workflow Version schemas ──────────────────────────────────────────────────


class PublishRequest(BaseModel):
    note: str | None = None


class WorkflowVersionResponse(BaseModel):
    id: uuid.UUID
    workflow_id: uuid.UUID | None
    org_id: uuid.UUID
    version_num: int
    note: str | None
    status: str
    definition: dict[str, Any]
    trigger_type: str
    trigger_config: dict[str, Any]
    created_by: uuid.UUID | None
    created_at: datetime

    model_config = {"from_attributes": True}
