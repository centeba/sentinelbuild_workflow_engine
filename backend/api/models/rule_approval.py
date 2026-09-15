"""Rule approval model — Gap 15: multi-person approval before publishing."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from api.constants import (  # noqa: F401 — re-exported for backward compat
    APPROVAL_STATUS_APPROVED,
    APPROVAL_STATUS_PENDING,
    APPROVAL_STATUS_REJECTED,
)
from shared.db import Base


class RuleApproval(Base):
    """
    Tracks an approval request for publishing a rule.

    Workflow:
      1. User calls POST /rules/{id}/request-approval → creates RuleApproval (pending)
      2. Each required approver calls POST /rules/approvals/{id}/approve or /reject
      3. Once all required approvers have approved → rule auto-published
      4. Any rejection → status = rejected, rule stays draft
    """

    __tablename__ = "rule_approvals"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    rule_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("rules.id", ondelete="CASCADE"),
        nullable=False,
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
    )
    requested_by: Mapped[str] = mapped_column(String(255), nullable=False)
    # List of approver emails required to sign off
    required_approvers: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list
    )
    # Approvals received: [{"email": "...", "approved_at": "...", "note": "..."}]
    approvals: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)
    # Snapshot of rule conditions/actions at time of request
    rule_snapshot: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=APPROVAL_STATUS_PENDING,
    )
    rejection_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
