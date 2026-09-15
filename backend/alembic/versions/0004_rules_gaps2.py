"""Rules engine: status, rule_type, version notes, correlation_id

Revision ID: 0004
Revises: 0003
Create Date: 2026-03-26
"""

import sqlalchemy as sa

from alembic import op

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── rules table ──────────────────────────────────────────────────────────
    # Gap 3: draft / published lifecycle
    op.add_column(
        "rules",
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="published",
        ),
    )
    # Gap 7: rule type (condition_tree | decision_table)
    op.add_column(
        "rules",
        sa.Column(
            "rule_type",
            sa.String(30),
            nullable=False,
            server_default="condition_tree",
        ),
    )
    # Composite index for the hot path: org + status + is_active
    op.create_index(
        "ix_rules_org_status_active",
        "rules",
        ["org_id", "status", "is_active"],
    )

    # ── rule_versions table ──────────────────────────────────────────────────
    # Gap 4: optional change note per snapshot
    op.add_column(
        "rule_versions",
        sa.Column("note", sa.Text, nullable=True),
    )
    # Snapshot the status + rule_type too
    op.add_column(
        "rule_versions",
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="published",
        ),
    )
    op.add_column(
        "rule_versions",
        sa.Column(
            "rule_type",
            sa.String(30),
            nullable=False,
            server_default="condition_tree",
        ),
    )

    # ── rule_audit_log table ─────────────────────────────────────────────────
    # Gap 5: pass-through correlation ID
    op.add_column(
        "rule_audit_log",
        sa.Column("correlation_id", sa.String(255), nullable=True),
    )
    op.create_index(
        "ix_audit_correlation",
        "rule_audit_log",
        ["correlation_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_audit_correlation", table_name="rule_audit_log")
    op.drop_column("rule_audit_log", "correlation_id")

    op.drop_column("rule_versions", "rule_type")
    op.drop_column("rule_versions", "status")
    op.drop_column("rule_versions", "note")

    op.drop_index("ix_rules_org_status_active", table_name="rules")
    op.drop_column("rules", "rule_type")
    op.drop_column("rules", "status")
