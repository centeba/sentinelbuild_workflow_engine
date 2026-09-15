"""Pack-contributed workflow-builder node types.

Each row is a single trigger / action / palette-group spec contributed
by an installed sb_pack manifest. The workflow builder palette reads
this table via ``GET /api/v1/node-types/registry`` and merges the
contents with the built-in node types so admins see domain-flavored
entries ("When a project is created") alongside generic ones
("Webhook trigger").

The table is keyed by ``(pack_name, kind, key)`` because the same
pack may re-install with updated specs at host startup; UPSERTs
overwrite the manifest_json in place rather than appending duplicate
rows. Org scoping is intentionally absent: pack manifests are
process-wide contributions (one host install = available to every
org that has the pack permission). Per-company opt-in lives at the
permission layer, not here.

Persisted by ``sb_core.packs.install.install_pack`` via the host's
``register_pack_node_type`` callback — see
``services/integration-hub/.../pack_bootstrap.py`` for the writer
shim and ``api/routers/internal.py`` for the HTTP entrypoint the
shim calls.
"""

from datetime import datetime
from typing import Any

from sqlalchemy import CheckConstraint, DateTime, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from shared.db import Base


class PackNodeType(Base):
    __tablename__ = "pack_node_types"
    __table_args__ = (
        UniqueConstraint(
            "pack_name",
            "kind",
            "key",
            name="uq_pack_node_types_pack_kind_key",
        ),
        CheckConstraint(
            "kind IN ('trigger','action','group','theme','data_domain','scraper_connector')",
            name="ck_pack_node_types_kind",
        ),
    )

    pack_name: Mapped[str] = mapped_column(String(64), primary_key=True)
    kind: Mapped[str] = mapped_column(String(32), primary_key=True)
    key: Mapped[str] = mapped_column(String(128), primary_key=True)
    manifest_json: Mapped[dict[str, Any]] = mapped_column(
        JSONB, nullable=False, default=dict
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )
