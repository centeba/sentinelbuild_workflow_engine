import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class RuleCreate(BaseModel):
    name: str
    description: str | None = None
    is_active: bool = True
    status: str = "published"  # Gap 3: draft | published
    rule_type: str = (
        "condition_tree"  # Gap 7/11: condition_tree | decision_table | javascript
    )
    priority: int = 100
    stop_on_match: bool = False
    trigger_events: list[str] = Field(default_factory=list)
    trigger_filter: dict[str, Any] = Field(default_factory=dict)
    conditions: dict[str, Any] = Field(default_factory=dict)
    actions: list[dict[str, Any]] = Field(default_factory=list)
    else_actions: list[dict[str, Any]] = Field(default_factory=list)
    # Gap 15: approval workflow
    approval_required: bool = False
    required_approvers: list[str] = Field(default_factory=list)


class RuleUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    is_active: bool | None = None
    status: str | None = None
    rule_type: str | None = None
    priority: int | None = None
    stop_on_match: bool | None = None
    trigger_events: list[str] | None = None
    trigger_filter: dict[str, Any] | None = None
    conditions: dict[str, Any] | None = None
    actions: list[dict[str, Any]] | None = None
    else_actions: list[dict[str, Any]] | None = None
    # Gap 4: optional change note — stored on the auto-snapshot, not on the rule itself
    version_note: str | None = None
    # Gap 15: approval workflow
    approval_required: bool | None = None
    required_approvers: list[str] | None = None


class RuleResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    description: str | None
    is_active: bool
    status: str
    rule_type: str
    priority: int
    stop_on_match: bool
    trigger_events: list[str]
    trigger_filter: dict[str, Any]
    conditions: dict[str, Any]
    actions: list[dict[str, Any]]
    else_actions: list[dict[str, Any]]
    # Gap 15
    approval_required: bool = False
    required_approvers: list[str] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class RuleTestRequest(BaseModel):
    """Simulate an event to see which rules would match and what actions would fire."""

    event_type: str
    event_data: dict[str, Any] = Field(default_factory=dict)
    dry_run: bool = True
    correlation_id: str | None = None  # Gap 5


class RuleTestResult(BaseModel):
    matched: bool
    rule_id: uuid.UUID
    rule_name: str
    rule_type: str = "condition_tree"
    conditions_result: bool
    actions_preview: list[dict[str, Any]]
    else_actions_preview: list[dict[str, Any]] = Field(default_factory=list)
    path: str = "then"


class RuleTestResponse(BaseModel):
    event_type: str
    event_data: dict[str, Any]
    matched_rules: list[RuleTestResult]
    total_rules_evaluated: int


# ── Version schemas ────────────────────────────────────────────────────────────


class RuleVersionResponse(BaseModel):
    id: uuid.UUID
    rule_id: uuid.UUID | None
    org_id: uuid.UUID
    version_num: int
    note: str | None  # Gap 4
    name: str
    description: str | None
    is_active: bool
    status: str
    rule_type: str
    priority: int
    stop_on_match: bool
    trigger_events: list[str]
    trigger_filter: dict[str, Any]
    conditions: dict[str, Any]
    actions: list[dict[str, Any]]
    else_actions: list[dict[str, Any]]
    approval_required: bool = False
    required_approvers: list[str] = Field(default_factory=list)
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Audit schemas ──────────────────────────────────────────────────────────────


class RuleAuditEntry(BaseModel):
    id: uuid.UUID
    rule_id: uuid.UUID | None
    org_id: uuid.UUID
    rule_name: str
    event_type: str
    matched: bool
    event_data: dict[str, Any]
    actions_executed: list[dict[str, Any]]
    elapsed_ms: int | None
    correlation_id: str | None  # Gap 5
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Analytics schemas (Gap 6) ─────────────────────────────────────────────────


class RuleAnalytics(BaseModel):
    total_evaluations: int
    match_count: int
    no_match_count: int
    match_rate_pct: float  # 0.0–100.0
    avg_elapsed_ms: float | None
    min_elapsed_ms: int | None
    max_elapsed_ms: int | None
    top_event_types: dict[str, int]  # {event_type: count}


# ── Batch schemas ──────────────────────────────────────────────────────────────


class BatchTestRequest(BaseModel):
    """Evaluate an array of records against all active rules."""

    event_type: str
    records: list[dict[str, Any]]
    dry_run: bool = True  # Gap 9: allow real execution when False
    correlation_id: str | None = None  # Gap 5: pass-through


class BatchRecordResult(BaseModel):
    record_index: int
    matched_rules: list[dict[str, Any]]
    elapsed_ms: int


class BatchTestResponse(BaseModel):
    event_type: str
    total_records: int
    results: list[BatchRecordResult]


# ── AI builder schemas (Gap 10) ───────────────────────────────────────────────


class AIRuleRequest(BaseModel):
    description: str
    event_type: str = "form_submit"


class AIRuleResponse(BaseModel):
    rule: dict[str, Any]  # The generated RuleCreate-compatible dict
    raw_prompt: str  # Echo of description for UX


# ── Rule flow schemas (Gap 12) ────────────────────────────────────────────────


class RuleFlowStepCreate(BaseModel):
    rule_id: uuid.UUID | None = None
    step_order: int = 0
    pass_output: bool = True
    label: str | None = None


class RuleFlowStepResponse(BaseModel):
    id: uuid.UUID
    flow_id: uuid.UUID
    rule_id: uuid.UUID | None
    step_order: int
    pass_output: bool
    label: str | None

    model_config = {"from_attributes": True}


class RuleFlowCreate(BaseModel):
    name: str
    description: str | None = None
    is_active: bool = True
    trigger_events: list[str] = Field(default_factory=list)
    steps: list[RuleFlowStepCreate] = Field(default_factory=list)


class RuleFlowUpdate(BaseModel):
    name: str | None = None
    description: str | None = None
    is_active: bool | None = None
    trigger_events: list[str] | None = None
    steps: list[RuleFlowStepCreate] | None = None


class RuleFlowResponse(BaseModel):
    id: uuid.UUID
    org_id: uuid.UUID
    name: str
    description: str | None
    is_active: bool
    trigger_events: list[str]
    steps: list[RuleFlowStepResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class RuleFlowExecuteRequest(BaseModel):
    event_type: str
    event_data: dict[str, Any] = Field(default_factory=dict)
    dry_run: bool = True


class RuleFlowExecuteResponse(BaseModel):
    flow_id: uuid.UUID
    event_type: str
    steps_executed: int
    step_results: list[dict[str, Any]]
    final_event_data: dict[str, Any]
    elapsed_ms: int


# ── Rule approval schemas (Gap 15) ────────────────────────────────────────────


class ApprovalActionRequest(BaseModel):
    """Approve or reject a pending rule approval."""

    action: str  # "approve" | "reject"
    note: str | None = None


class RuleApprovalResponse(BaseModel):
    id: uuid.UUID
    rule_id: uuid.UUID
    org_id: uuid.UUID
    requested_by: str
    required_approvers: list[str]
    approvals: list[dict[str, Any]]
    rule_snapshot: dict[str, Any] | None
    status: str
    rejection_note: str | None
    created_at: datetime
    resolved_at: datetime | None

    model_config = {"from_attributes": True}


# ── JS rule validation schema ─────────────────────────────────────────────────


class JSRuleValidateRequest(BaseModel):
    code: str


class JSRuleValidateResponse(BaseModel):
    valid: bool
    error: str | None = None
