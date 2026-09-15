import json
from pathlib import Path
from typing import Any, cast

from fastapi import APIRouter, HTTPException

from shared.redis_client import get_redis

router = APIRouter(prefix="/translations", tags=["translations"])

_DIR = Path(__file__).parent.parent.parent / "translations"


@router.get("/{namespace}")
async def get_translations(namespace: str, locale: str = "en-US") -> dict[str, Any]:
    redis = await get_redis()
    key = f"i18n:{locale}:{namespace}"
    if cached := await redis.get(key):
        return {"locale": locale, "namespace": namespace, "data": json.loads(cached)}
    data = _load(locale, namespace) or _load("en-US", namespace)
    if data is None:
        raise HTTPException(
            404,
            detail=f"No translation: locale={locale}, namespace={namespace}",
        )
    await redis.setex(key, 3600, json.dumps(data))
    return {"locale": locale, "namespace": namespace, "data": data}


def _load(locale: str, namespace: str) -> dict[str, Any] | None:
    p = _DIR / locale / f"{namespace}.json"
    if not p.is_file():
        return None
    return cast(dict[str, Any], json.loads(p.read_text(encoding="utf-8")))
