"""Encryption-key rotation for mit-stack credentials (SB-08).

mit-stack encrypts ``credentials.encrypted_data`` with a **direct** key (no data
key / envelope — see ``shared.encryption``): the payload is AES-256-GCM'd straight
under a key derived from ``ENCRYPTION_KEY``. Rotating that key therefore has to
fully decrypt every credential with the old key and re-encrypt it with the new one
(there is no wrapped DEK to cheaply re-wrap).

The sweep reads/writes the raw ``encrypted_data`` bytes through a plain view of the
``credentials`` table and takes both keys explicitly (the runtime is wired to a
single key, whereas rotation needs the old and new at once). Resumable via
trial-decrypt, since no key version is recorded.
"""

import base64
import os
import uuid

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import Column, LargeBinary, MetaData, Table, Uuid, select, update
from sqlalchemy.ext.asyncio import AsyncSession


def derive_key(encryption_key: str) -> bytes:
    """Derive the 32-byte AES key from an ``ENCRYPTION_KEY`` string — matches
    ``shared.encryption._get_key`` so old/new keys are derived identically."""
    return base64.urlsafe_b64decode(encryption_key + "==")[:32]


def rewrap_credential(blob: bytes, *, old_key: bytes, new_key: bytes) -> bytes:
    """Decrypt one ``nonce || ciphertext`` blob with ``old_key`` and re-encrypt it
    under ``new_key`` with a fresh nonce. Raises if it won't decrypt under
    ``old_key``."""
    plaintext = AESGCM(old_key).decrypt(blob[:12], blob[12:], None)
    nonce = os.urandom(12)
    return nonce + AESGCM(new_key).encrypt(nonce, plaintext, None)


def _credentials_table() -> Table:
    """A minimal view of ``credentials`` (id + encrypted_data) so the ciphertext
    bytes are read/written raw, independent of the full ORM model."""
    return Table(
        "credentials",
        MetaData(),
        Column("id", Uuid, primary_key=True),
        Column("encrypted_data", LargeBinary),
    )


async def rewrap_all_credentials(
    session: AsyncSession, *, old_key: bytes, new_key: bytes
) -> int:
    """Re-encrypt every credential's ``encrypted_data`` from the old key to the
    new one. Returns the number of rows re-encrypted.

    Resumable despite no key version being recorded: a row that won't decrypt
    under the old key is verified to decrypt under the new one (already rotated)
    and skipped; a row that decrypts under NEITHER key raises (corruption)."""
    table = _credentials_table()
    rows = (
        (await session.execute(select(table).where(table.c.encrypted_data.isnot(None))))
        .mappings()
        .all()
    )
    rewrapped = 0
    for row in rows:
        cred_id: uuid.UUID = row["id"]
        blob: bytes = row["encrypted_data"]
        try:
            new_blob = rewrap_credential(blob, old_key=old_key, new_key=new_key)
        except Exception:
            try:
                AESGCM(new_key).decrypt(blob[:12], blob[12:], None)
            except Exception as verify_exc:
                raise ValueError(
                    f"credential {cred_id}: decrypts under neither the old nor the "
                    f"new key (possible corruption)"
                ) from verify_exc
            continue  # already rotated under the new key
        await session.execute(
            update(table).where(table.c.id == cred_id).values(encrypted_data=new_blob)
        )
        rewrapped += 1
    await session.commit()
    return rewrapped
