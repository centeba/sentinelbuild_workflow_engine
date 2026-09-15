"""Rules engine enhancements: else_actions, rule_versions, rule_audit_log

Revision ID: 0003
Revises: 0002
Create Date: 2026-03-26
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── 1. Add else_actions to existing rules table ──────────────────────────
    op.add_column(
        "rules",
        sa.Column(
            "else_actions", JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
    )

    # ── 2. Create rule_versions table ────────────────────────────────────────
    op.create_table(
        "rule_versions",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        # SET NULL so versions survive rule deletion
        sa.Column(
            "rule_id",
            UUID(as_uuid=True),
            sa.ForeignKey("rules.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("version_num", sa.Integer, nullable=False),
        sa.Column("name", sa.Text, nullable=False),
        sa.Column("description", sa.Text, nullable=True),
        sa.Column("is_active", sa.Boolean, nullable=False, server_default="true"),
        sa.Column("priority", sa.Integer, nullable=False, server_default="100"),
        sa.Column("stop_on_match", sa.Boolean, nullable=False, server_default="false"),
        sa.Column(
            "trigger_events",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "trigger_filter",
            JSONB,
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
        sa.Column(
            "conditions", JSONB, nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column(
            "actions", JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        sa.Column(
            "else_actions", JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")
        ),
    )
    op.create_index(
        "ix_rule_versions_rule_ver", "rule_versions", ["rule_id", "version_num"]
    )
    op.create_index("ix_rule_versions_org", "rule_versions", ["org_id", "created_at"])

    # ── 3. Create rule_audit_log table ───────────────────────────────────────
    op.create_table(
        "rule_audit_log",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        # SET NULL so audit rows survive rule deletion
        sa.Column(
            "rule_id",
            UUID(as_uuid=True),
            sa.ForeignKey("rules.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "org_id",
            UUID(as_uuid=True),
            sa.ForeignKey("organizations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        # Denormalised so deleted-rule audits still make sense
        sa.Column("rule_name", sa.Text, nullable=False),
        sa.Column("event_type", sa.Text, nullable=False),
        sa.Column("matched", sa.Boolean, nullable=False),
        sa.Column(
            "event_data", JSONB, nullable=False, server_default=sa.text("'{}'::jsonb")
        ),
        sa.Column(
            "actions_executed",
            JSONB,
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("elapsed_ms", sa.Integer, nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()")
        ),
    )
    op.create_index("ix_audit_org_created", "rule_audit_log", ["org_id", "created_at"])
    op.create_index(
        "ix_audit_rule_created", "rule_audit_log", ["rule_id", "created_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_audit_rule_created", table_name="rule_audit_log")
    op.drop_index("ix_audit_org_created", table_name="rule_audit_log")
    op.drop_table("rule_audit_log")

    op.drop_index("ix_rule_versions_org", table_name="rule_versions")
    op.drop_index("ix_rule_versions_rule_ver", table_name="rule_versions")
    op.drop_table("rule_versions")

    op.drop_column("rules", "else_actions")
