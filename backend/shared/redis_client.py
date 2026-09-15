from redis.asyncio import Redis, from_url

from shared.config import get_settings

settings = get_settings()

_redis: Redis | None = None


async def get_redis() -> Redis:
    global _redis
    if _redis is None:
        _redis = from_url(settings.redis_url, decode_responses=True)
    return _redis


async def close_redis() -> None:
    global _redis
    if _redis is not None:
        await _redis.aclose()
        _redis = None


class RedisKeys:
    @staticmethod
    def workflow(workflow_id: str) -> str:
        return f"workflow:{workflow_id}"

    @staticmethod
    def exec_status(exec_id: str) -> str:
        return f"exec:status:{exec_id}"

    @staticmethod
    def exec_logs(exec_id: str) -> str:
        # Channel format is also documented (with the consumer-side
        # contract) in ``sentinelbuild_sdk.channels.exec_logs_channel``.
        # If this format changes, also update:
        #   • packages/sentinelbuild_python_sdk/src/sentinelbuild_sdk/channels.py
        #   • integration-hub subscription_bus.py TOPIC_TO_REDIS_RULES
        # Tests at test_subscription_bus.py assert the literal so a drift
        # surfaces in CI.
        return f"exec:logs:{exec_id}"

    @staticmethod
    def webhook_ratelimit(org_id: str) -> str:
        return f"ratelimit:webhook:{org_id}"

    @staticmethod
    def scraper_lock(session_id: str) -> str:
        return f"scraper:lock:{session_id}"

    @staticmethod
    def jwt_blacklist(jti: str) -> str:
        return f"jwt:blacklist:{jti}"

    @staticmethod
    def rules_active(org_id: str) -> str:
        """All published+active rules for an org — cached as JSON."""
        return f"rules:active:{org_id}"
