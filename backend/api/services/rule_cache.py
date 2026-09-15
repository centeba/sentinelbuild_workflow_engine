"""
Rule Cache Service (Gap 1)

Caches all published+active rules per org in Redis to avoid hitting the DB
on every process_event() call.

Cache key: rules:active:{org_id}
Value:     JSON-encoded list of rule dicts (all columns serialised)
TTL:       settings.rule_cache_ttl seconds (default 300)

Invalidation:
  - Call invalidate() on any rule create / update / delete / publish / unpublish
  - TTL-based expiry acts as a safety net

Usage:
    rules = await get_cached_rules(org_id, db)   # list[Rule]
    await invalidate(org_id)                      # clear cache
"""

import json
import uuid
from typing import Any, cast

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from api.models.rule import RULE_STATUS_PUBLISHED, Rule
from shared.config import get_settings
from shared.redis_client import RedisKeys, get_redis

_settings = get_settings()


def _rule_to_dict(rule: Rule) -> dict[str, Any]:
    """Serialise a Rule ORM object to a plain dict for Redis storage."""
    return {
        "id": str(rule.id),
        "org_id": str(rule.org_id),
        "name": rule.name,
        "description": rule.description,
        "is_active": rule.is_active,
        "status": rule.status,
        "rule_type": rule.rule_type,
        "priority": rule.priority,
        "stop_on_match": rule.stop_on_match,
        "trigger_events": rule.trigger_events,
        "trigger_filter": rule.trigger_filter,
        "conditions": rule.conditions,
        "actions": rule.actions,
        "else_actions": rule.else_actions,
    }


async def get_cached_rules(org_id: str, db: AsyncSession) -> list[dict[str, Any]]:
    """
    Return all published+active rules for an org.
    Tries Redis first; falls back to PostgreSQL and warms the cache.
    Returns raw dicts (not ORM objects) to avoid session binding issues.
    """
    redis = await get_redis()
    key = RedisKeys.rules_active(org_id)

    cached = await redis.get(key)
    if cached:
        return cast(list[dict[str, Any]], json.loads(cached))

    # Cache miss — load from DB
    result = await db.execute(
        select(Rule)
        .where(
            Rule.org_id == uuid.UUID(org_id),
            Rule.is_active.is_(True),
            Rule.status == RULE_STATUS_PUBLISHED,
        )
        .order_by(Rule.priority.asc())
    )
    rules = result.scalars().all()
    rule_dicts = [_rule_to_dict(r) for r in rules]

    # Write to cache
    await redis.setex(key, _settings.rule_cache_ttl, json.dumps(rule_dicts))
    return rule_dicts


async def invalidate(org_id: str) -> None:
    """Delete the rule cache for an org. Call this on any rule mutation."""
    redis = await get_redis()
    await redis.delete(RedisKeys.rules_active(str(org_id)))
