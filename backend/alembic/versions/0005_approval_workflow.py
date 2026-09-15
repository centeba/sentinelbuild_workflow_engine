"""Approval columns on workflow_executions for wait/approval node.

Revision ID: 0005
Revises: 0004
Create Date: 2026-03-28
"""

import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── wait_approval support on workflow_executions ──────────────────────────
    # Approval lifecycle: None → "pending" → "approved" | "rejected" | "timeout"
    op.add_column(
        "workflow_executions",
        sa.Column("approval_status", sa.String(20), nullable=True),
    )
    # Signed token embedded in email approve/reject links (UUID)
    op.add_column(
        "workflow_executions",
        sa.Column("approval_token", sa.String(255), nullable=True, unique=True),
    )
    # node_id of the wait_approval node — used by the signal endpoint
    op.add_column(
        "workflow_executions",
        sa.Column("approval_node_id", sa.String(100), nullable=True),
    )
    # Name / email of the person who actioned the approval
    op.add_column(
        "workflow_executions",
        sa.Column("approved_by", sa.String(255), nullable=True),
    )
    # Optional note from the approver
    op.add_column(
        "workflow_executions",
        sa.Column("approval_note", sa.Text, nullable=True),
    )
    # Expiry timestamp for the approval link
    op.add_column(
        "workflow_executions",
        sa.Column("approval_expires_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_executions_approval_token",
        "workflow_executions",
        ["approval_token"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("ix_executions_approval_token", table_name="workflow_executions")
    op.drop_column("workflow_executions", "approval_expires_at")
    op.drop_column("workflow_executions", "approval_note")
    op.drop_column("workflow_executions", "approved_by")
    op.drop_column("workflow_executions", "approval_node_id")
    op.drop_column("workflow_executions", "approval_token")
    op.drop_column("workflow_executions", "approval_status")
