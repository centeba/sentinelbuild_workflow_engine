import contextvars
import uuid
from collections.abc import AsyncGenerator

from smart_llm.service_runtime import resolve_pool_sizing
from sqlalchemy import event, text
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from shared.config import get_settings

settings = get_settings()

_pool_size, _max_overflow = resolve_pool_sizing(
    settings.db_pool_size, settings.db_max_overflow
)
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    pool_size=_pool_size,
    max_overflow=_max_overflow,
)

AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


# ── Tenant isolation via Postgres Row-Level Security (HARDENING-PLAN A2) ──────
#
# RLS policies scope the tenant-private tables (credentials, integrations,
# scraper_sessions — see the RLS migration) using the per-transaction GUC
# ``app.current_org``. The tenant flows through a per-request/task contextvar
# that the auth dependency stamps from the verified JWT ``org_id``; Temporal
# activities that read these tables outside the request path (they carry their
# own ``org_id``) stamp it too via ``set_current_org``. An engine ``begin``
# listener applies it as a LOCAL GUC on each transaction (Postgres only).
_current_org: contextvars.ContextVar[str] = contextvars.ContextVar(
    "mit_stack_current_org", default=""
)


def set_current_org(org: uuid.UUID | str | None) -> None:
    """Set the tenant for the current request/task. Empty = no tenant (RLS then
    returns zero rows on the RLS'd tables). Called by the auth dependency and by
    worker activities before they touch a tenant-private table."""
    _current_org.set(str(org) if org else "")


@event.listens_for(engine.sync_engine, "begin")
def _stamp_tenant_guc(conn: Connection) -> None:
    if conn.dialect.name != "postgresql":
        return  # sqlite (tests) has no set_config / RLS
    conn.execute(
        text("SELECT set_config('app.current_org', :org, true)"),
        {"org": _current_org.get()},
    )


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
