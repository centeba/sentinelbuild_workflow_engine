"""Allow 'scraper_connector' kind on pack_node_types.

Packs now contribute a `scraper_connector` kind (multi-tenant authenticated-
scraper templates — site knowledge only, no secrets) alongside
trigger/action/group/theme/data_domain. The literal 'scraper_connector' is 17
chars, so widen the kind column from varchar(16) → varchar(32) as well as the
CHECK constraint.

Revision ID: 0012
Revises: 0011
"""

import sqlalchemy as sa

from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None

_OLD = "kind IN ('trigger','action','group','theme','data_domain')"
_NEW = "kind IN ('trigger','action','group','theme','data_domain','scraper_connector')"
_NAME = "ck_pack_node_types_kind"


def upgrade() -> None:
    op.alter_column(
        "pack_node_types",
        "kind",
        existing_type=sa.String(16),
        type_=sa.String(32),
        existing_nullable=False,
    )
    op.drop_constraint(_NAME, "pack_node_types", type_="check")
    op.create_check_constraint(_NAME, "pack_node_types", _NEW)


def downgrade() -> None:
    op.drop_constraint(_NAME, "pack_node_types", type_="check")
    op.create_check_constraint(_NAME, "pack_node_types", _OLD)
    op.alter_column(
        "pack_node_types",
        "kind",
        existing_type=sa.String(32),
        type_=sa.String(16),
        existing_nullable=False,
    )
