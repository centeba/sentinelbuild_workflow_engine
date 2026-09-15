import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, ForeignKey, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from api.constants import (
    EXEC_STATUS_PENDING,
    NODE_EXEC_STATUS_PENDING,
    TRIGGER_MANUAL,
)
from shared.db import Base


class WorkflowExecution(Base):
    __tablename__ = "workflow_executions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    workflow_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflows.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    org_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Which published version this execution ran (null for legacy executions)
    version_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflow_versions.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    # Temporal workflow run ID
    temporal_workflow_id: Mapped[str | None] = mapped_column(
        String(255), unique=True, nullable=True
    )
    # see api.constants: EXEC_STATUS_*
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=EXEC_STATUS_PENDING, index=True
    )
    input_data: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    output_data: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Trigger info
    # see api.constants: TRIGGER_*
    trigger_type: Mapped[str] = mapped_column(
        String(50), nullable=False, default=TRIGGER_MANUAL
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    # ── Approval flow (wait_approval node) ────────────────────────────────────
    # None → WORKFLOW_APPROVAL_PENDING → WORKFLOW_APPROVAL_APPROVED | _REJECTED | _TIMEOUT
    approval_status: Mapped[str | None] = mapped_column(String(20), nullable=True)
    approval_token: Mapped[str | None] = mapped_column(
        String(255), nullable=True, unique=True
    )
    approval_node_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    approved_by: Mapped[str | None] = mapped_column(String(255), nullable=True)
    approval_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    approval_expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    workflow: Mapped["Workflow"] = relationship(  # type: ignore[name-defined]  # SQLAlchemy cross-module relationship forward-ref; top-level import would cycle, TYPE_CHECKING disallowed
        "Workflow", back_populates="executions", lazy="select"
    )
    node_executions: Mapped[list["NodeExecution"]] = relationship(
        "NodeExecution",
        back_populates="execution",
        lazy="noload",
        cascade="all, delete-orphan",
    )


class NodeExecution(Base):
    __tablename__ = "node_executions"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    execution_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("workflow_executions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    node_id: Mapped[str] = mapped_column(String(100), nullable=False)
    node_type: Mapped[str] = mapped_column(String(50), nullable=False)
    # see api.constants: NODE_EXEC_STATUS_*
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=NODE_EXEC_STATUS_PENDING
    )
    input_data: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    output_data: Mapped[dict[str, Any]] = mapped_column(
        JSONB, default=dict, server_default="{}"
    )
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    execution: Mapped["WorkflowExecution"] = relationship(
        "WorkflowExecution", back_populates="node_executions", lazy="noload"
    )
