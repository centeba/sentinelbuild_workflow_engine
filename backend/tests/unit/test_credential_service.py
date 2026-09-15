"""
Unit tests for shared.encryption (encrypt, decrypt, generate_key).

The encryption module uses AES-256-GCM under the hood.  The key is loaded from
settings.encryption_key, so we patch get_settings to inject a test key.

A Fernet-compatible base64 key is used as the test key because generate_key()
returns one and the module accepts that format.
"""

from unittest.mock import MagicMock, patch

import pytest
from cryptography.fernet import Fernet

from shared.encryption import decrypt, encrypt, generate_key

# Generate a single stable test key for the whole module.
# Using Fernet.generate_key() because that is exactly what generate_key()
# returns and what the module's _get_key() is designed to accept.
_TEST_KEY: str = Fernet.generate_key().decode()


def _make_settings(key: str = _TEST_KEY) -> MagicMock:
    """Return a mock settings object with the given encryption_key."""
    s = MagicMock()
    s.encryption_key = key
    return s


# ─── generate_key ─────────────────────────────────────────────────────────────


def test_generate_key_returns_string():
    """generate_key() returns a non-empty string."""
    key = generate_key()
    assert isinstance(key, str)
    assert len(key) > 0


def test_generate_key_is_valid_fernet_key():
    """generate_key() output can be used directly by the cryptography library."""
    key = generate_key()
    # Should not raise
    Fernet(key.encode())


def test_generate_key_unique_each_call():
    """Two calls to generate_key() produce different keys."""
    assert generate_key() != generate_key()


# ─── encrypt ──────────────────────────────────────────────────────────────────


def test_encrypt_returns_bytes():
    """encrypt() returns bytes."""
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        result = encrypt("hello")
    assert isinstance(result, bytes)


def test_encrypt_output_differs_from_plaintext():
    """encrypt() output is not the plain-text encoded as bytes."""
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        result = encrypt("hello")
    assert result != b"hello"


def test_encrypt_same_text_produces_different_ciphertexts():
    """Each call to encrypt() uses a random nonce, so ciphertexts differ."""
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        c1 = encrypt("same plaintext")
        c2 = encrypt("same plaintext")
    assert c1 != c2


# ─── decrypt ──────────────────────────────────────────────────────────────────


def test_decrypt_roundtrip_simple_string():
    """decrypt(encrypt(text)) returns the original text."""
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        ciphertext = encrypt("Hello, World!")
        result = decrypt(ciphertext)
    assert result == "Hello, World!"


def test_decrypt_roundtrip_json_string():
    """decrypt(encrypt(json_str)) returns the original JSON string."""
    json_str = '{"user": "alice", "score": 99}'
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        result = decrypt(encrypt(json_str))
    assert result == json_str


def test_decrypt_roundtrip_empty_string():
    """decrypt(encrypt('')) returns empty string."""
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        result = decrypt(encrypt(""))
    assert result == ""


def test_decrypt_roundtrip_unicode():
    """decrypt(encrypt(unicode_str)) handles non-ASCII characters."""
    text = "Héllo Wörld — 日本語"
    with patch("shared.encryption.get_settings", return_value=_make_settings()):
        result = decrypt(encrypt(text))
    assert result == text


def test_decrypt_wrong_key_raises_exception():
    """Decrypting with a different key raises an exception."""
    other_key = Fernet.generate_key().decode()
    with patch(
        "shared.encryption.get_settings", return_value=_make_settings(_TEST_KEY)
    ):
        ciphertext = encrypt("secret data")

    with pytest.raises(Exception):
        with patch(
            "shared.encryption.get_settings", return_value=_make_settings(other_key)
        ):
            decrypt(ciphertext)


def test_decrypt_truncated_ciphertext_raises():
    """Passing garbage bytes to decrypt raises an exception."""
    with pytest.raises(Exception):
        with patch("shared.encryption.get_settings", return_value=_make_settings()):
            decrypt(b"not-valid-ciphertext")


# ─── missing encryption_key ───────────────────────────────────────────────────


def test_encrypt_missing_key_raises_runtime_error():
    """encrypt() with no encryption_key raises RuntimeError with a helpful message."""
    with patch("shared.encryption.get_settings", return_value=_make_settings(key="")):
        with pytest.raises(RuntimeError, match="ENCRYPTION_KEY"):
            encrypt("test")


def test_decrypt_missing_key_raises_runtime_error():
    """decrypt() with no encryption_key raises RuntimeError."""
    # Encrypt with a valid key first so we have real ciphertext
    with patch(
        "shared.encryption.get_settings", return_value=_make_settings(_TEST_KEY)
    ):
        ciphertext = encrypt("test")

    with patch("shared.encryption.get_settings", return_value=_make_settings(key="")):
        with pytest.raises(RuntimeError, match="ENCRYPTION_KEY"):
            decrypt(ciphertext)
