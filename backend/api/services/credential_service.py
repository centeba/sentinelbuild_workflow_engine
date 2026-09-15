import json
import uuid
from typing import Any, cast

from sqlalchemy.ext.asyncio import AsyncSession

from api.models.credential import Credential
from shared.encryption import decrypt, encrypt


async def create_credential(
    db: AsyncSession,
    org_id: uuid.UUID,
    user_id: uuid.UUID,
    name: str,
    type_: str,
    secret_data: dict[str, Any],
    metadata: dict[str, Any],
) -> Credential:
    encrypted = encrypt(json.dumps(secret_data))
    cred = Credential(
        org_id=org_id,
        created_by=user_id,
        name=name,
        type=type_,
        encrypted_data=encrypted,
        metadata_=metadata,
    )
    db.add(cred)
    await db.flush()
    return cred


def get_secret_data(credential: Credential) -> dict[str, Any]:
    """Decrypt and return credential secret data. Never expose via API."""
    return cast(dict[str, Any], json.loads(decrypt(credential.encrypted_data)))
