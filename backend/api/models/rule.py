import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.constants import (  # noqa: F401 — re-exported for backward compat
    RULE_STATUS_DRAFT,
    RULE_STATUS_PUBLISHED,
    RULE_TYPE_CONDITION_TREE,
    RULE_TYPE_DECISION_TABLE,
    RULE_TYPE_JAVASCRIPT,
)
from shared.db import Base

__all__ = [
    "RULE_STATUS_DRAFT",
    "RULE_STATUS_PUBLISHED",
    "RULE_TYPE_CONDITION_TREE",
    "RULE_TYPE_DECISION_TABLE",
    "RULE_TYPE_JAVASCRIPT",
    "Rule",
]


class Rule(Base):
    __tablename__ = "rules"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Office scoping (NULL = company-shared). Office id lives in user-master;
    # no cross-service FK. NULL artifacts are visible to all offices.
    office_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True, index=True
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Gap 3: lifecycle — only "published" rules are evaluated at runtime
    # "draft" rules are invisible to process_event() and the cache
    status: Mapped[str] = mapped_column(
        String(20), default=RULE_STATUS_PUBLISHED, nullable=False
    )

    # Gap 7: rule type — controls how `conditions` is interpreted
    rule_type: Mapped[str] = mapped_column(
        String(30), default=RULE_TYPE_CONDITION_TREE, nullable=False
    )

    # Lower number = evaluated first
    priority: Mapped[int] = mapped_column(Integer, default=100, nullable=False)

    # Stop evaluating lower-priority rules if this one fires
    stop_on_match: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # List of event types that trigger evaluation:
    # form_submit | workflow_complete | workflow_fail | webhook | schedule | manual
    trigger_events: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list
    )

    # Optional filter: only process if event_data matches these key/value pairs
    trigger_filter: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )

    # For rule_type = condition_tree:
    #   {"combinator": "and", "rules": [...]}
    # For rule_type = decision_table:
    #   {
    #     "input_columns":  [{"field": "data.tier",     "label": "Tier"}],
    #     "output_columns": [{"field": "discount_pct",  "label": "Discount %"}],
    #     "rows": [
    #       {"id": "r1", "conditions": [{"operator": "eq",  "value": "gold"}],
    #                    "outputs":    [{"value": "20"}], "annotation": "Gold tier"},
    #       {"id": "r2", "conditions": [{"operator": "ANY"}],
    #                    "outputs":    [{"value": "0"}],  "annotation": "Default"}
    #     ]
    #   }
    conditions: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )

    # Actions to execute when conditions match (condition_tree only; ignored for decision_table)
    actions: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)

    # Actions to execute when conditions do NOT match (fallback / else path)
    else_actions: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)

    # Gap 15: rule approval workflow
    # When True, a rule must be approved before it can be published
    approval_required: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    # List of approver email addresses required to sign off
    required_approvers: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
