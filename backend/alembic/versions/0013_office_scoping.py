"""office_id on workflows, rules, forms (office-scoped artifacts)

Revision ID: 0013
Revises: 0012
Create Date: 2026-06-25

Nullable office_id on each Automate artifact. NULL = company-shared (visible to
all offices); set = belongs to that office's subtree. The office tree lives in
user-master, so there's no cross-service FK — just a UUID + index.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None

_TABLES = ("workflows", "rules", "forms")


def upgrade() -> None:
    for t in _TABLES:
        op.add_column(t, sa.Column("office_id", UUID(as_uuid=True), nullable=True))
        op.create_index(f"ix_{t}_office_id", t, ["office_id"])


def downgrade() -> None:
    for t in _TABLES:
        op.drop_index(f"ix_{t}_office_id", table_name=t)
        op.drop_column(t, "office_id")
