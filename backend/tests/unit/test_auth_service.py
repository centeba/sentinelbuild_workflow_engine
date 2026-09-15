"""
Unit tests for api.services.auth_service.

Covers hash_password, verify_password, create_access_token,
create_refresh_token, and decode_token — all pure/synchronous helpers
that do not require a database.
"""

import uuid

import pytest

from api.services.auth_service import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    verify_password,
)

# Stable test identifiers used across all token tests
_USER_ID = str(uuid.uuid4())
_ORG_ID = str(uuid.uuid4())


# ─── hash_password / verify_password ─────────────────────────────────────────


def test_hash_password_returns_string():
    """hash_password returns a string."""
    result = hash_password("s3cr3t")
    assert isinstance(result, str)


def test_hash_password_differs_from_plaintext():
    """hash_password output is not the plain-text password."""
    plain = "my-password-123"
    assert hash_password(plain) != plain


def test_hash_password_produces_different_hashes_each_call():
    """Two calls with the same password produce different hashes (bcrypt salting)."""
    h1 = hash_password("same-password")
    h2 = hash_password("same-password")
    assert h1 != h2


def test_verify_password_correct():
    """verify_password returns True for the matching plain-text password."""
    plain = "correct-horse-battery"
    hashed = hash_password(plain)
    assert verify_password(plain, hashed) is True


def test_verify_password_wrong():
    """verify_password returns False for an incorrect password."""
    hashed = hash_password("correct")
    assert verify_password("wrong", hashed) is False


# ─── create_access_token ──────────────────────────────────────────────────────


def test_create_access_token_returns_string():
    """create_access_token returns a non-empty string."""
    token = create_access_token(_USER_ID, _ORG_ID)
    assert isinstance(token, str)
    assert len(token) > 0


def test_create_access_token_looks_like_jwt():
    """Access token has three dot-separated segments (JWT format)."""
    token = create_access_token(_USER_ID, _ORG_ID)
    parts = token.split(".")
    assert len(parts) == 3


# ─── create_refresh_token ─────────────────────────────────────────────────────


def test_create_refresh_token_returns_string():
    """create_refresh_token returns a non-empty string."""
    token = create_refresh_token(_USER_ID, _ORG_ID)
    assert isinstance(token, str)
    assert len(token) > 0


def test_access_and_refresh_tokens_differ():
    """Access token and refresh token for same user are different strings."""
    access = create_access_token(_USER_ID, _ORG_ID)
    refresh = create_refresh_token(_USER_ID, _ORG_ID)
    assert access != refresh


# ─── decode_token ─────────────────────────────────────────────────────────────


def test_decode_access_token_contains_required_claims():
    """Decoded access token contains sub, org, type='access', and jti."""
    token = create_access_token(_USER_ID, _ORG_ID)
    payload = decode_token(token)
    assert payload["sub"] == _USER_ID
    assert payload["org"] == _ORG_ID
    assert payload["type"] == "access"
    assert "jti" in payload


def test_decode_refresh_token_type_is_refresh():
    """Decoded refresh token has type='refresh'."""
    token = create_refresh_token(_USER_ID, _ORG_ID)
    payload = decode_token(token)
    assert payload["type"] == "refresh"


def test_decode_refresh_token_contains_sub_and_org():
    """Decoded refresh token contains sub and org claims."""
    token = create_refresh_token(_USER_ID, _ORG_ID)
    payload = decode_token(token)
    assert payload["sub"] == _USER_ID
    assert payload["org"] == _ORG_ID


def test_access_token_type_mismatch_detectable():
    """
    An access token decoded as refresh can be detected via the 'type' claim.
    The application layer should check payload['type'] == 'refresh'.
    """
    access_token = create_access_token(_USER_ID, _ORG_ID)
    payload = decode_token(access_token)
    # decode_token itself does not reject by type — that is the router's job.
    # We verify that the type claim is available for inspection.
    assert payload["type"] == "access"
    assert payload["type"] != "refresh"


def test_tampered_token_raises_on_decode():
    """Tampering with a token signature causes decode_token to raise an exception."""
    token = create_access_token(_USER_ID, _ORG_ID)
    # Corrupt the signature (last segment)
    parts = token.split(".")
    parts[-1] = parts[-1][:-4] + "XXXX"
    tampered = ".".join(parts)
    with pytest.raises(Exception):
        decode_token(tampered)


def test_completely_invalid_token_raises():
    """A completely bogus string raises an exception on decode."""
    with pytest.raises(Exception):
        decode_token("not.a.jwt")


def test_decode_token_preserves_jti_uniqueness():
    """Two tokens created for the same user have different jti values."""
    t1 = create_access_token(_USER_ID, _ORG_ID)
    t2 = create_access_token(_USER_ID, _ORG_ID)
    p1 = decode_token(t1)
    p2 = decode_token(t2)
    assert p1["jti"] != p2["jti"]
