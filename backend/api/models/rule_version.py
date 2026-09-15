import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from shared.db import Base


class RuleVersion(Base):
    """Immutable snapshot of a Rule taken before every PUT update."""

    __tablename__ = "rule_versions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # Nullable — survives rule deletion
    rule_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("rules.id", ondelete="SET NULL"), nullable=True
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
    )

    version_num: Mapped[int] = mapped_column(Integer, nullable=False)

    # Gap 4: optional human-readable change note
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    name: Mapped[str] = mapped_column(Text, nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="published", nullable=False)
    rule_type: Mapped[str] = mapped_column(
        String(30), default="condition_tree", nullable=False
    )
    priority: Mapped[int] = mapped_column(Integer, default=100, nullable=False)
    stop_on_match: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    trigger_events: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list
    )
    trigger_filter: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    conditions: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    actions: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)
    else_actions: Mapped[list[Any]] = mapped_column(JSONB, nullable=False, default=list)

    # Gap 15: approval workflow (snapshot)
    approval_required: Mapped[bool] = mapped_column(
        Boolean, default=False, nullable=False
    )
    required_approvers: Mapped[list[Any]] = mapped_column(
        JSONB, nullable=False, default=list
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
