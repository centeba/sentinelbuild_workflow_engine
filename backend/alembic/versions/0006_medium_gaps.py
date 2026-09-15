"""Medium-priority gaps: scripted rules, rule flows, rule approvals

Revision ID: 0006
Revises: 0005
Create Date: 2026-03-28
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

from alembic import op

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── Gap 11: JavaScript rule type ──────────────────────────────────────────
    # No column needed — JS code is stored in `conditions.code` JSON field.
    # Just extend the rule_type column constraint comment; no DDL required.
    # (The existing rule_type VARCHAR(30) column already accommodates "javascript")

    # ── Gap 14: hit_policy for decision tables ────────────────────────────────
    # Also stored in the conditions JSON — no new column needed.

    # ── Gap 15: Rule approval ─────────────────────────────────────────────────
    # Add approval fields to rules
    op.add_column(
        "rules",
        sa.Column(
            "approval_required",
            sa.Boolean,
            nullable=False,
            server_default="false",
        ),
    )
    op.add_column(
        "rules",
        sa.Column(
            "required_approvers",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )

    # Mirror on rule_versions
    op.add_column(
        "rule_versions",
        sa.Column(
            "approval_required",
            sa.Boolean,
            nullable=False,
            server_default="false",
        ),
    )
    op.add_column(
        "rule_versions",
        sa.Column(
            "required_approvers",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )

    # rule_approvals table — tracks per-rule approval requests
    op.create_table(
        "rule_approvals",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "rule_id",
            UUID(as_uuid=True),
            sa.ForeignKey("rules.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # Who requested approval
        sa.Column("requested_by", sa.String(255), nullable=False),
        # Ordered list of approver emails required
        sa.Column(
            "required_approvers",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        # Approvals received: [{email, approved_at, note}]
        sa.Column(
            "approvals", JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        # Snapshot of the rule at time of request
        sa.Column("rule_snapshot", JSONB, nullable=True),
        # Status: pending | approved | rejected
        sa.Column(
            "status", sa.String(20), nullable=False, server_default=sa.text("'pending'")
        ),
        sa.Column("rejection_note", sa.Text, nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_rule_approvals_rule", "rule_approvals", ["rule_id"])
    op.create_index(
        "ix_rule_approvals_org_status", "rule_approvals", ["org_id", "status"]
    )

    # ── Gap 12: Rule flows ────────────────────────────────────────────────────
    op.create_table(
        "rule_flows",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column(
            "trigger_events",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    op.create_table(
        "rule_flow_steps",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "flow_id",
            UUID(as_uuid=True),
            sa.ForeignKey("rule_flows.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "rule_id",
            UUID(as_uuid=True),
            sa.ForeignKey("rules.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("step_order", sa.Integer, nullable=False, server_default="0"),
        # When true, matched actions' set_field mutations carry into next step
        sa.Column("pass_output", sa.Boolean, nullable=False, server_default="true"),
        # Optional label shown in the UI
        sa.Column("label", sa.String(255), nullable=True),
    )
    op.create_index(
        "ix_rule_flow_steps_order", "rule_flow_steps", ["flow_id", "step_order"]
    )


def downgrade() -> None:
    op.drop_index("ix_rule_flow_steps_order", table_name="rule_flow_steps")
    op.drop_table("rule_flow_steps")
    op.drop_table("rule_flows")

    op.drop_index("ix_rule_approvals_org_status", table_name="rule_approvals")
    op.drop_index("ix_rule_approvals_rule", table_name="rule_approvals")
    op.drop_table("rule_approvals")

    op.drop_column("rule_versions", "required_approvers")
    op.drop_column("rule_versions", "approval_required")
    op.drop_column("rules", "required_approvers")
    op.drop_column("rules", "approval_required")
