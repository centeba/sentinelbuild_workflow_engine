import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from shared.db import Base


class WorkflowVersion(Base):
    """Immutable snapshot of a Workflow definition taken on publish."""

    __tablename__ = "workflow_versions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # Nullable — survives workflow deletion
    workflow_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflows.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    version_num: Mapped[int] = mapped_column(Integer, nullable=False)

    # Optional human-readable change note
    note: Mapped[str | None] = mapped_column(Text, nullable=True)

    # "draft" | "active" | "archived"
    status: Mapped[str] = mapped_column(String(20), default="draft", nullable=False)

    # Snapshot of workflow state at publish time
    definition: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )
    trigger_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default="manual"
    )
    trigger_config: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )

    created_by: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
