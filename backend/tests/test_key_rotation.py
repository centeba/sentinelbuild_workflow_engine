"""Encryption-key rotation for mit-stack credentials (SB-08).

Direct-key scheme (no DEK): rotation fully decrypts each credential with the old
key and re-encrypts with the new. Verified against a raw SQLite ``credentials``
table with two random AES keys.
"""

import os
import uuid
from collections.abc import AsyncIterator
from typing import Any

import pytest
import pytest_asyncio
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import Column, LargeBinary, MetaData, Table, Uuid, insert, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from shared.key_rotation import rewrap_all_credentials, rewrap_credential

pytestmark = pytest.mark.asyncio

_META = MetaData()
_CREDS = Table(
    "credentials",
    _META,
    Column("id", Uuid, primary_key=True),
    Column("encrypted_data", LargeBinary),
)


def _seal(plaintext: str, key: bytes) -> bytes:
    nonce = os.urandom(12)
    return nonce + AESGCM(key).encrypt(nonce, plaintext.encode(), None)


@pytest_asyncio.fixture
async def sessions() -> AsyncIterator[async_sessionmaker[Any]]:
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(_META.create_all)
    yield async_sessionmaker(engine, expire_on_commit=False)
    await engine.dispose()


async def test_rewrap_credential_round_trip() -> None:
    old, new = os.urandom(32), os.urandom(32)
    blob = _seal("s3cr3t", old)

    rotated = rewrap_credential(blob, old_key=old, new_key=new)

    assert AESGCM(new).decrypt(rotated[:12], rotated[12:], None).decode() == "s3cr3t"
    with pytest.raises(InvalidTag):
        AESGCM(old).decrypt(rotated[:12], rotated[12:], None)


async def test_rewrap_all_credentials_rotates_and_is_resumable(
    sessions: async_sessionmaker[Any],
) -> None:
    old, new = os.urandom(32), os.urandom(32)
    cred_id = uuid.uuid4()
    async with sessions() as s:
        await s.execute(
            insert(_CREDS).values(id=cred_id, encrypted_data=_seal("api-key-123", old))
        )
        await s.commit()

    async with sessions() as s:
        assert await rewrap_all_credentials(s, old_key=old, new_key=new) == 1

    async with sessions() as s:
        row = (
            (await s.execute(select(_CREDS).where(_CREDS.c.id == cred_id)))
            .mappings()
            .one()
        )
        blob: bytes = row["encrypted_data"]
        assert AESGCM(new).decrypt(blob[:12], blob[12:], None).decode() == "api-key-123"
        with pytest.raises(InvalidTag):
            AESGCM(old).decrypt(blob[:12], blob[12:], None)

    # Resumable: a second sweep re-encrypts nothing (already on the new key).
    async with sessions() as s:
        assert await rewrap_all_credentials(s, old_key=old, new_key=new) == 0
