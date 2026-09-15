"""
OAuth2 Browser Flow (Gap 9)

Supports Google (Gmail / Drive) and Microsoft (Outlook / OneDrive) OAuth2.

Flow:
  1. Frontend calls  GET /api/v1/oauth2/start?connector=google&name=MyGmail
     → returns {"auth_url": "https://accounts.google.com/o/oauth2/v2/auth?..."}
  2. Frontend opens auth_url in new browser tab
  3. User grants consent
  4. Google/Microsoft redirects to  GET /api/v1/oauth2/callback?code=...&state=...
     → Backend exchanges code for tokens, creates encrypted Credential, returns HTML page
  5. Frontend (polling) detects new credential via GET /credentials?oauth_pending=true
     and shows it in the list

State is stored in Redis (key: oauth2:state:{state}) with 10-minute TTL.
"""

import json
import secrets
import uuid
from typing import Annotated, Any
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.ext.asyncio import AsyncSession

from api.deps import CurrentUser, get_current_user
from api.models.credential import Credential
from shared.config import get_settings
from shared.db import get_db
from shared.encryption import encrypt
from shared.redis_client import get_redis

router = APIRouter(prefix="/oauth2", tags=["oauth2"])
_settings = get_settings()

# ── Connector definitions ─────────────────────────────────────────────────────

_CONNECTORS: dict[str, dict[str, Any]] = {
    "google": {
        "auth_url": "https://accounts.google.com/o/oauth2/v2/auth",
        "token_url": "https://oauth2.googleapis.com/token",
        "scopes": [
            "https://www.googleapis.com/auth/gmail.send",
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/drive",
            "https://www.googleapis.com/auth/spreadsheets",
            "openid",
            "email",
        ],
        "client_id_setting": "google_oauth_client_id",
        "client_secret_setting": "google_oauth_client_secret",
        "label": "Google (Gmail / Drive)",
    },
    "microsoft": {
        "auth_url": "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        "token_url": "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        "scopes": [
            "offline_access",
            "Mail.Send",
            "Mail.Read",
            "Files.ReadWrite",
            "User.Read",
        ],
        "client_id_setting": "microsoft_oauth_client_id",
        "client_secret_setting": "microsoft_oauth_client_secret",
        "label": "Microsoft (Outlook / OneDrive)",
    },
}


@router.get("/start")
async def oauth2_start(
    connector: Annotated[str, Query(description="'google' or 'microsoft'")],
    current: Annotated[CurrentUser, Depends(get_current_user)],
    # pre-existing bug fixed: default cannot be set inside Annotated Query() in current FastAPI (crashed app import); moved to = default
    name: Annotated[
        str, Query(description="Friendly name for the new credential")
    ] = "",
) -> dict[str, str]:
    """
    Generate an OAuth2 authorization URL for the requested connector.
    Returns {"auth_url": "..."} — the frontend opens this in a new tab.
    """
    cfg = _CONNECTORS.get(connector)
    if not cfg:
        raise HTTPException(status_code=422, detail=f"Unknown connector: {connector}")

    client_id = getattr(_settings, cfg["client_id_setting"], None)
    if not client_id:
        raise HTTPException(
            status_code=503,
            detail=f"{connector} OAuth2 is not configured on this server. "
            f"Set {cfg['client_id_setting'].upper()} in the environment.",
        )

    state = secrets.token_urlsafe(32)
    redirect_uri = _redirect_uri()

    # Persist state in Redis for 10 minutes
    redis = await get_redis()
    await redis.setex(
        f"oauth2:state:{state}",
        600,
        json.dumps(
            {
                "connector": connector,
                "org_id": str(current.org_id),
                "user_id": str(current.user_id),
                "name": name or cfg["label"],
            }
        ),
    )

    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(cfg["scopes"]),
        "state": state,
        "access_type": "offline",  # Google: request refresh token
        "prompt": "consent",  # Google: force consent to always get refresh_token
    }
    auth_url = f"{cfg['auth_url']}?{urlencode(params)}"
    return {"auth_url": auth_url}


@router.get("/callback")
async def oauth2_callback(
    db: Annotated[AsyncSession, Depends(get_db)],
    # pre-existing bug fixed: default cannot be set inside Annotated Query() in current FastAPI (crashed app import); moved to = default
    code: Annotated[str | None, Query()] = None,
    state: Annotated[str | None, Query()] = None,
    error: Annotated[str | None, Query()] = None,
) -> HTMLResponse:
    """
    OAuth2 callback — exchanges the code for tokens, creates the credential.
    Returns HTML that closes the popup tab and notifies the opener.
    """
    if error:
        return HTMLResponse(_result_html(f"OAuth2 error: {error}", success=False))
    if not code or not state:
        return HTMLResponse(_result_html("Missing code or state.", success=False))

    # Retrieve and delete state
    redis = await get_redis()
    state_key = f"oauth2:state:{state}"
    raw = await redis.get(state_key)
    if not raw:
        return HTMLResponse(
            _result_html("State expired or invalid. Please try again.", success=False)
        )
    await redis.delete(state_key)
    state_data = json.loads(raw)

    connector = state_data["connector"]
    cfg = _CONNECTORS.get(connector)
    if not cfg:
        return HTMLResponse(_result_html("Unknown connector in state.", success=False))

    client_id = getattr(_settings, cfg["client_id_setting"], None)
    client_secret = getattr(_settings, cfg["client_secret_setting"], None)
    redirect_uri = _redirect_uri()

    # Exchange code for tokens
    try:
        async with httpx.AsyncClient() as client:
            resp = await client.post(
                cfg["token_url"],
                data={
                    "grant_type": "authorization_code",
                    "code": code,
                    "redirect_uri": redirect_uri,
                    "client_id": client_id,
                    "client_secret": client_secret,
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=15,
            )
            resp.raise_for_status()
            token_data = resp.json()
    except Exception as exc:
        return HTMLResponse(
            _result_html(f"Token exchange failed: {exc}", success=False)
        )

    # Persist credential (encrypted)
    secret_data = {
        "access_token": token_data.get("access_token", ""),
        "refresh_token": token_data.get("refresh_token", ""),
        "expires_in": token_data.get("expires_in", 3600),
        "scope": token_data.get("scope", ""),
        "token_type": token_data.get("token_type", "Bearer"),
    }
    cred = Credential(
        id=uuid.uuid4(),
        org_id=uuid.UUID(state_data["org_id"]),
        name=state_data.get("name", cfg["label"]),
        type="oauth2",
        encrypted_data=encrypt(json.dumps(secret_data)),
        metadata_={"connector": connector, "oauth2_pending": False},
    )
    db.add(cred)
    await db.flush()

    return HTMLResponse(
        _result_html(
            f"Connected! <strong>{cred.name}</strong> is ready to use. You may close this tab.",
            success=True,
            cred_id=str(cred.id),
        )
    )


def _redirect_uri() -> str:
    base = _settings.public_base_url.rstrip("/")
    return f"{base}/api/v1/oauth2/callback"


def _result_html(message: str, success: bool, cred_id: str = "") -> str:
    color = "#22C55E" if success else "#EF4444"
    icon = "✓" if success else "✗"
    # Post a message to the opener window so the Flutter app can react
    js = (
        f"""
    if (window.opener) {{
      window.opener.postMessage({{type: 'oauth2_complete', success: {str(success).lower()},
                                 credId: '{cred_id}'}}, '*');
    }}
    setTimeout(() => window.close(), 2000);
    """
        if success
        else "setTimeout(() => window.close(), 4000);"
    )
    return f"""<!DOCTYPE html>
<html>
<head><title>Mit Stack – OAuth2</title></head>
<body style="font-family:-apple-system,sans-serif;background:#0F1117;color:#E2E8F0;
             display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
  <div style="text-align:center;padding:40px;background:#1A1D2E;border-radius:16px;
              border:1px solid #2D3148;max-width:420px;">
    <div style="font-size:48px;color:{color};margin-bottom:16px;">{icon}</div>
    <p style="font-size:15px;color:#E2E8F0;">{message}</p>
    <p style="font-size:12px;color:#475569;margin-top:16px;">This window will close automatically…</p>
  </div>
  <script>{js}</script>
</body>
</html>"""
