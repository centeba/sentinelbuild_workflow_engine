"""AES-256-GCM credential encryption using the cryptography library."""

import base64
import os

from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from shared.config import get_settings


def _get_key() -> bytes:
    settings = get_settings()
    key = settings.encryption_key
    if not key:
        raise RuntimeError(
            "ENCRYPTION_KEY is not set. Generate one with:\n"
            '  python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"'
        )
    # Accept both raw Fernet key (44 chars base64) and hex keys
    raw = base64.urlsafe_b64decode(key + "==")
    return raw[:32]  # AES-256 needs 32 bytes


def encrypt(plaintext: str) -> bytes:
    """Encrypt plaintext string → bytes (nonce + ciphertext)."""
    key = _get_key()
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)  # 96-bit nonce for GCM
    ct = aesgcm.encrypt(nonce, plaintext.encode(), None)
    return nonce + ct


def decrypt(ciphertext: bytes) -> str:
    """Decrypt bytes → plaintext string."""
    key = _get_key()
    aesgcm = AESGCM(key)
    nonce = ciphertext[:12]
    ct = ciphertext[12:]
    return aesgcm.decrypt(nonce, ct, None).decode()


def generate_key() -> str:
    """Generate a new Fernet-compatible encryption key."""
    return Fernet.generate_key().decode()
