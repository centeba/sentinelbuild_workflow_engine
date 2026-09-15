"""One-shot data-migration scripts for mit-stack.

Distinct from the Alembic ``alembic/`` tree — those run on every
deploy and own DDL. Modules in this package are runnable on demand
(typically via ``python -m migrations.<name>`` from the
mit-stack-backend root) and own *data* migrations or maintenance
sweeps that don't fit Alembic's rev-graph model. Each module documents
when and how to run it.
"""
