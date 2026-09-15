"""Pack-contributed workflow-builder node types.

Each row is a single trigger / action / palette-group spec declared
by an installed sb_pack manifest. The workflow builder palette reads
this table to render restoration-flavored (or any other pack's)
entries alongside the built-in node types.

Revision ID: 0009
Revises: 0008
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pack_node_types",
        sa.Column("pack_name", sa.String(64), primary_key=True),
        sa.Column("kind", sa.String(16), primary_key=True),
        sa.Column("key", sa.String(128), primary_key=True),
        sa.Column("manifest_json", JSONB(), nullable=False, server_default="{}"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.CheckConstraint(
            "kind IN ('trigger','action','group','theme')",
            name="ck_pack_node_types_kind",
        ),
        sa.UniqueConstraint(
            "pack_name",
            "kind",
            "key",
            name="uq_pack_node_types_pack_kind_key",
        ),
    )
    # The pack_name index helps the palette query (filter contributions
    # by installed packs) without scanning the whole table.
    op.create_index(
        "ix_pack_node_types_pack_name",
        "pack_node_types",
        ["pack_name"],
    )
    op.create_index(
        "ix_pack_node_types_kind",
        "pack_node_types",
        ["kind"],
    )


def downgrade() -> None:
    op.drop_index("ix_pack_node_types_kind", table_name="pack_node_types")
    op.drop_index("ix_pack_node_types_pack_name", table_name="pack_node_types")
    op.drop_table("pack_node_types")
