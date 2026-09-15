"""Add workflow versioning: workflow_versions table, active_version_id on workflows, version_id on executions

Revision ID: 0007
Revises: 0006
Create Date: 2026-04-06
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB, UUID

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. Create workflow_versions table
    op.create_table(
        "workflow_versions",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("workflow_id", UUID(as_uuid=True), nullable=True),
        sa.Column("org_id", UUID(as_uuid=True), nullable=False),
        sa.Column("version_num", sa.Integer(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="draft"),
        sa.Column("definition", JSONB(), nullable=False, server_default="{}"),
        sa.Column(
            "trigger_type", sa.String(50), nullable=False, server_default="manual"
        ),
        sa.Column("trigger_config", JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_by", UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now()
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["workflow_id"], ["workflows.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["org_id"], ["organizations.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["created_by"], ["users.id"], ondelete="SET NULL"),
    )
    op.create_index(
        "ix_workflow_versions_workflow_id", "workflow_versions", ["workflow_id"]
    )
    op.create_index("ix_workflow_versions_org_id", "workflow_versions", ["org_id"])

    # 2. Add active_version_id to workflows
    op.add_column(
        "workflows",
        sa.Column("active_version_id", UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_workflows_active_version_id",
        "workflows",
        "workflow_versions",
        ["active_version_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # 3. Add version_id to workflow_executions
    op.add_column(
        "workflow_executions",
        sa.Column("version_id", UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_workflow_executions_version_id",
        "workflow_executions",
        "workflow_versions",
        ["version_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_workflow_executions_version_id", "workflow_executions", ["version_id"]
    )

    # 4. Data migration: create version 1 for each existing workflow
    #    so existing workflows have an active published version
    op.execute("""
        INSERT INTO workflow_versions (id, workflow_id, org_id, version_num, status, definition, trigger_type, trigger_config, created_by, created_at)
        SELECT
            gen_random_uuid(),
            w.id,
            w.org_id,
            1,
            'active',
            w.definition,
            w.trigger_type,
            w.trigger_config,
            w.created_by,
            NOW()
        FROM workflows w
    """)

    # Point each workflow's active_version_id to its newly created version
    op.execute("""
        UPDATE workflows w
        SET active_version_id = wv.id
        FROM workflow_versions wv
        WHERE wv.workflow_id = w.id AND wv.version_num = 1
    """)


def downgrade() -> None:
    # Remove version_id from executions
    op.drop_constraint(
        "fk_workflow_executions_version_id", "workflow_executions", type_="foreignkey"
    )
    op.drop_index("ix_workflow_executions_version_id", table_name="workflow_executions")
    op.drop_column("workflow_executions", "version_id")

    # Remove active_version_id from workflows
    op.drop_constraint(
        "fk_workflows_active_version_id", "workflows", type_="foreignkey"
    )
    op.drop_column("workflows", "active_version_id")

    # Drop workflow_versions table
    op.drop_index("ix_workflow_versions_org_id", table_name="workflow_versions")
    op.drop_index("ix_workflow_versions_workflow_id", table_name="workflow_versions")
    op.drop_table("workflow_versions")
