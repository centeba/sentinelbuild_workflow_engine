import asyncio
import os
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

import api.models  # noqa: F401 — registers all ORM models
from alembic import context

# Import all models so Alembic can detect them
from shared.db import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Allow DATABASE_URL env var to override alembic.ini URL (used in Docker).
# RLS activation split (A2): migrations run as the privileged owner role when
# MIGRATION_DB_USER is set (so ALTER TABLE / CREATE POLICY succeed), while the app
# runtime connects as a non-superuser role so FORCE ROW LEVEL SECURITY bites.
# No-op when MIGRATION_DB_USER is unset.
from smart_llm.service_runtime import migration_db_url  # noqa: E402

_db_url = os.environ.get("DATABASE_URL")
if _db_url:
    config.set_main_option("sqlalchemy.url", migration_db_url(_db_url))

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        version_table="alembic_version",
        version_table_schema="workflow",
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    # HA: serialize concurrent migrate-on-boot across co-booting replicas
    # (best-effort, lock_timeout-bounded — falls through to unserialized).
    from smart_llm.service_runtime import acquire_migration_lock

    acquire_migration_lock(connection)
    # Create the version-table schema before alembic tries to write
    # ``workflow.alembic_version`` — otherwise the very first ``upgrade``
    # against a fresh database fails ("schema \"workflow\" does not exist").
    # Every per-client deployment runs ``alembic upgrade head`` from empty, so
    # migrations must be self-contained and not rely on an out-of-band
    # ``init-db.sql`` (which only runs via Postgres's initdb hook, absent on
    # managed Postgres). Own committed transaction (mirrors authz) so it doesn't
    # interfere with alembic's migration transaction.
    with connection.begin():
        connection.exec_driver_sql('CREATE SCHEMA IF NOT EXISTS "workflow"')
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        version_table="alembic_version",
        version_table_schema="workflow",
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
