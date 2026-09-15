"""Playwright-based web scraper activity with session support."""

import json
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import UTC
from typing import TYPE_CHECKING, Any, cast

from temporalio import activity
from temporalio.exceptions import ApplicationError

from shared.ssrf import SsrfError, validate_url

if TYPE_CHECKING:
    # Playwright is a heavy dependency the runtime imports lazily inside each
    # activity (see the local `from playwright.async_api import async_playwright`
    # calls); keep it out of module import so worker startup does not pay for it.
    from playwright.async_api import Page


def _guard_nav(url: str) -> None:
    """SSRF guard (S3) — reject navigation to internal/metadata/loopback hosts."""
    try:
        validate_url(url)
    except SsrfError as exc:
        raise ApplicationError(
            f"Blocked navigation to {url}: {exc}",
            non_retryable=True,
            type="SsrfBlocked",
        )


@dataclass
class ScrapeParams:
    url: str
    selectors: list[dict[str, str]] = field(default_factory=list)
    actions: list[dict[str, Any]] = field(default_factory=list)
    session_id: str | None = None
    org_id: str | None = None
    screenshot: bool = False
    wait_for_selector: str | None = None
    timeout_ms: int = 30000


# Many sites (WAFs / bot protection) 403 the default headless Chromium signature.
# Presenting a realistic desktop-Chrome user-agent + headers, disabling the
# AutomationControlled blink feature, and hiding navigator.webdriver gets past
# the common header/JS bot checks. Generic — applies to every scrape/login.
_DEFAULT_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
_STEALTH_HEADERS = {
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": (
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
    ),
}
_LAUNCH_ARGS = ["--disable-blink-features=AutomationControlled"]
_WEBDRIVER_PATCH = "Object.defineProperty(navigator,'webdriver',{get:()=>undefined})"


async def _robust_fill(page: "Page", selector: str, value: str) -> None:
    """Fill an input reliably across hardened login forms.

    Some forms (typically ``autocomplete="off"`` logins) wipe values written via
    the normal fill/keystroke path on the resulting input event, leaving the
    field — and ASP.NET RequiredFieldValidators — seeing it as empty. Try the
    normal fill first (real keystrokes, best for most sites); if the value
    doesn't stick, set the DOM value directly and dispatch input/change so both
    client frameworks and validators observe it.
    """
    try:
        await page.fill(selector, value)
        if (await page.input_value(selector)) == value:
            return
    except Exception:
        pass
    await page.evaluate(
        """([s, v]) => {
            const el = document.querySelector(s);
            if (!el) return;
            el.value = v;
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
        }""",
        [selector, value],
    )


def _interp_login_value(value: Any, ctx: dict[str, Any]) -> Any:
    """Interpolate {{username}} / {{password}} / {{field.<key>}} in a step value.

    Non-string values pass through unchanged.
    """
    if not isinstance(value, str):
        return value
    out = value.replace("{{username}}", str(ctx.get("username", "")))
    out = out.replace("{{password}}", str(ctx.get("password", "")))
    for k, v in (ctx.get("field") or {}).items():
        out = out.replace("{{field." + k + "}}", str(v))
    return out


async def _run_login_steps(
    page: "Page",
    steps: list[dict[str, Any]],
    login_config: dict[str, Any],
    username: str,
    password: str,
    totp_secret: str | None,
) -> bool:
    """Execute a declarative login step list; returns whether a TOTP code ran.

    Step ``action``s: ``goto`` (value=url), ``fill`` (selector,value),
    ``click`` (selector), ``wait`` (seconds), ``wait_for`` (selector),
    ``press`` (value=key, default Enter), ``totp`` (uses login_config["mfa"] +
    the secret; per-step selector overrides allowed), ``assert_url``
    (value=substring), ``assert_selector`` (selector). ``value`` supports
    {{username}} / {{password}} / {{field.<key>}} interpolation, where
    ``field`` = login_config["field_values"] (tenant identifiers).
    """
    import asyncio

    ctx = {
        "username": username,
        "password": password,
        "field": login_config.get("field_values", {}) or {},
    }
    mfa_applied = False
    for step in steps or []:
        action = (step.get("action") or "").lower()
        sel = step.get("selector")
        val = _interp_login_value(step.get("value", ""), ctx)
        if action == "goto":
            if val:
                _guard_nav(val)
            await page.goto(val or page.url, wait_until="networkidle")
        elif action == "fill":
            if sel:
                await _robust_fill(page, sel, val)
        elif action == "click":
            if sel:
                await page.click(sel)
                await page.wait_for_load_state("networkidle")
        elif action == "wait":
            await asyncio.sleep(float(step.get("seconds", 1)))
        elif action == "wait_for":
            if sel:
                await page.wait_for_selector(sel)
        elif action == "press":
            await page.keyboard.press(val or "Enter")
            await page.wait_for_load_state("networkidle")
        elif action == "totp":
            mfa = dict(login_config.get("mfa", {}) or {})
            for k in (
                "code_selector",
                "submit_selector",
                "challenge_url_contains",
                "remember_selector",
            ):
                if step.get(k) is not None:
                    mfa[k] = step[k]
            mfa_applied = await _maybe_complete_totp(page, mfa, totp_secret)
        elif action == "assert_url":
            if val and val.lower() not in page.url.lower():
                raise ApplicationError(
                    f"Login assert_url failed: {val!r} not in {page.url}"
                )
        elif action == "assert_selector":
            if sel and not await page.query_selector(sel):
                raise ApplicationError(
                    f"Login assert_selector failed: {sel!r} not found"
                )
        else:
            raise ApplicationError(f"Unknown login step action: {action!r}")
    return mfa_applied


@activity.defn
async def scrape_page(params: ScrapeParams) -> dict[str, Any]:
    from playwright.async_api import async_playwright

    from shared.redis_client import RedisKeys, get_redis

    storage_state = None
    lock_key: str | None = None
    redis = None

    # Load session if provided + acquire session lock so two concurrent
    # scrapes don't race on the same persisted cookies. The lock has a
    # 30-minute TTL as a backstop, but we now release it in a finally
    # block — the previous code leaked the lock for the full TTL after
    # any Playwright failure.
    if params.session_id and params.org_id:
        storage_state = await _load_session(params.session_id, params.org_id)
        redis = await get_redis()
        lock_key = RedisKeys.scraper_lock(params.session_id)
        await redis.setex(lock_key, 1800, "locked")

    try:
        async with async_playwright() as pw:
            browser = await pw.chromium.launch(headless=True, args=_LAUNCH_ARGS)
            ctx_kwargs: dict[str, Any] = {
                "user_agent": _DEFAULT_UA,
                "locale": "en-US",
                "extra_http_headers": _STEALTH_HEADERS,
            }
            if storage_state:
                ctx_kwargs["storage_state"] = storage_state

            context = await browser.new_context(**ctx_kwargs)
            context.set_default_timeout(params.timeout_ms)
            await context.add_init_script(_WEBDRIVER_PATCH)
            page = await context.new_page()

            try:
                _guard_nav(params.url)
                await page.goto(
                    params.url, wait_until="networkidle", timeout=params.timeout_ms
                )

                if params.wait_for_selector:
                    await page.wait_for_selector(
                        params.wait_for_selector, timeout=params.timeout_ms
                    )

                # Execute actions (click, fill, etc.)
                for action in params.actions:
                    await _execute_action(page, action)

                # Extract data using selectors
                extracted: dict[str, Any] = {}
                for selector_def in params.selectors:
                    name = selector_def["name"]
                    css = selector_def.get("css")
                    xpath = selector_def.get("xpath")
                    attr = selector_def.get("attr", "innerText")
                    multiple = selector_def.get("multiple", False)

                    sel = css or xpath
                    if not sel:
                        continue

                    if multiple:
                        elements = await page.locator(sel).all()
                        extracted[name] = []
                        for el in elements:
                            if attr == "innerText":
                                extracted[name].append(await el.inner_text())
                            else:
                                extracted[name].append(await el.get_attribute(attr))
                    else:
                        locator = page.locator(sel).first
                        if attr == "innerText":
                            extracted[name] = await locator.inner_text()
                        elif attr == "innerHTML":
                            extracted[name] = await locator.inner_html()
                        else:
                            extracted[name] = await locator.get_attribute(attr)

                result: dict[str, Any] = {
                    "url": page.url,
                    "data": extracted,
                }

                if params.screenshot:
                    screenshot_bytes = await page.screenshot(type="png")
                    import base64

                    result["screenshot_base64"] = base64.b64encode(
                        screenshot_bytes
                    ).decode()

                # Save updated session state back to DB
                if params.session_id and params.org_id:
                    new_state = await context.storage_state()
                    await _save_session(params.session_id, params.org_id, new_state)

                return result

            finally:
                await context.close()
                await browser.close()
    finally:
        # Release the Redis lock on every exit path — success, network
        # error, Playwright crash. The 1800s TTL still acts as a
        # safety net for the case where the worker dies before this
        # block runs.
        if redis is not None and lock_key is not None:
            try:
                await redis.delete(lock_key)
            except Exception:
                # Best-effort cleanup; TTL will reap eventually.
                pass


@activity.defn
async def login_and_capture_session(params: dict[str, Any]) -> dict[str, Any]:
    """Login to a site and capture session for future use."""
    from playwright.async_api import async_playwright

    session_id = params["session_id"]
    org_id = params["org_id"]
    login_url = params["login_url"]
    username = params["username"]
    password = params["password"]
    login_config = params.get("login_config", {})

    username_selector = login_config.get(
        "username_selector",
        'input[type="email"], input[name="username"], input[name="email"]',
    )
    password_selector = login_config.get("password_selector", 'input[type="password"]')
    submit_selector = login_config.get("submit_selector", 'button[type="submit"]')
    # Optional TOTP/MFA. The secret travels with the credential (params), the
    # page selectors with login_config["mfa"]; both are required to run the step.
    totp_secret = params.get("totp_secret")

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True, args=_LAUNCH_ARGS)
        context = await browser.new_context(
            user_agent=login_config.get("user_agent", _DEFAULT_UA),
            locale="en-US",
            extra_http_headers=_STEALTH_HEADERS,
        )
        await context.add_init_script(_WEBDRIVER_PATCH)
        page = await context.new_page()

        _guard_nav(login_url)
        await page.goto(login_url, wait_until="networkidle")

        steps = login_config.get("login_steps")
        if steps:
            # Declarative path: an ordered step list — handles multi-page logins,
            # custom field order, consent clicks, etc. RMS ships this as its preset.
            mfa_applied = await _run_login_steps(
                page, steps, login_config, username, password, totp_secret
            )
        else:
            # Legacy fixed shape: extra_fields → username → password → submit →
            # optional TOTP. Used when a connector declares no login_steps.
            for field in login_config.get("extra_fields", []) or []:
                sel = field.get("selector")
                if sel:
                    await _robust_fill(page, sel, str(field.get("value", "")))
            await _robust_fill(page, username_selector, username)
            await _robust_fill(page, password_selector, password)
            await page.click(submit_selector)
            await page.wait_for_load_state("networkidle")
            # MFA/TOTP — only runs when configured AND we landed on the challenge
            # page; raises loudly on a non-TOTP challenge (SMS/push).
            mfa_applied = await _maybe_complete_totp(
                page, login_config.get("mfa"), totp_secret
            )

        # Verify we actually reached an authenticated page before persisting —
        # otherwise a rejected login / lingering challenge would save a useless
        # logged-out session (the cause of the earlier 1-cookie capture).
        final_url = page.url
        verified = _login_succeeded(final_url, login_config)
        if verified and login_config.get("success_selector"):
            verified = bool(await page.query_selector(login_config["success_selector"]))
        if not verified:
            await context.close()
            await browser.close()
            raise ApplicationError(
                f"Login did not reach an authenticated page (final_url={final_url})"
            )

        storage_state = await context.storage_state()
        await context.close()
        await browser.close()

    # Save to DB
    await _save_session(session_id, org_id, storage_state)
    return {
        "status": "captured",
        "cookies_count": len(storage_state.get("cookies", [])),
        "mfa_applied": mfa_applied,
        "final_url": final_url,
    }


def _login_succeeded(final_url: str, login_config: dict[str, Any]) -> bool:
    """URL-based success check. Configurable, backward-compatible.

    ``login_config`` keys (all optional): ``failure_url_contains`` (list — any
    match ⇒ failed, e.g. ["Login.aspx", "SetupMFA"]), ``success_url_contains``
    (str — must be present). With none set, returns True (no-op) so existing
    generic scrapes are unaffected; ``success_selector`` is checked by the caller.
    """
    url = (final_url or "").lower()
    for bad in login_config.get("failure_url_contains", []) or []:
        if bad and bad.lower() in url:
            return False
    success = login_config.get("success_url_contains")
    if success:
        return success.lower() in url
    return True


async def _maybe_complete_totp(
    page: "Page", mfa: dict[str, Any] | None, totp_secret: str | None
) -> bool:
    """If the post-login page is a TOTP challenge, fill + submit the code.

    ``mfa`` (from login_config): {code_selector, submit_selector,
    challenge_url_contains?, remember_selector?}. Returns True if a code was
    submitted, False if there was no challenge to act on. Raises ApplicationError
    when a challenge IS present but can't be satisfied with TOTP (no secret,
    missing selectors, or a non-TOTP method like SMS/push) — so the caller never
    persists a half-authenticated session.
    """
    if not mfa:
        return False

    code_selector = mfa.get("code_selector")
    submit_selector = mfa.get("submit_selector")
    marker = (mfa.get("challenge_url_contains") or "").lower()
    on_marked_url = bool(marker) and marker in page.url.lower()
    has_code_field = bool(code_selector) and bool(
        await page.query_selector(cast(str, code_selector))
    )

    # No challenge at all → nothing to do (non-MFA logins are unaffected).
    if not on_marked_url and not has_code_field:
        return False

    # A challenge is present. From here, failing to satisfy it must be loud.
    if not totp_secret:
        raise ApplicationError(
            "MFA challenge present but no TOTP secret is configured for this credential"
        )
    if not code_selector or not submit_selector:
        raise ApplicationError(
            "MFA challenge present but login_config.mfa lacks code_selector/submit_selector"
        )
    if not has_code_field:
        # On the challenge URL but no TOTP input — likely SMS/push/email or a
        # changed page. Don't guess; surface it for manual re-auth.
        raise ApplicationError(
            "MFA challenge is not a TOTP code field (method may have changed) — "
            "manual re-auth required"
        )

    import pyotp

    totp = pyotp.TOTP(totp_secret)
    remember = mfa.get("remember_selector")
    # Submit the current code; if the field is still present afterward the code
    # may have rolled over the 30s window between generate and submit — retry once
    # with the next window's code.
    for attempt in range(2):
        await _robust_fill(page, code_selector, totp.now())
        if remember and attempt == 0:
            try:
                await page.check(remember)
            except Exception:
                pass
        await page.click(submit_selector)
        await page.wait_for_load_state("networkidle")
        if not await page.query_selector(code_selector):
            return True  # advanced past the challenge
    return True  # submitted; final success is asserted by the caller


@activity.defn
async def refresh_scraper_session(params: dict[str, Any]) -> dict[str, Any]:
    """Re-authenticate a stored scraper session.

    Loads the ``ScraperSession`` (org-scoped) and its linked ``Credential``,
    decrypts the username/password, then drives the existing headless login flow
    (``login_and_capture_session``) to capture a fresh encrypted browser session.
    Backs the ``RefreshScraperSessionWorkflow`` dispatched by
    ``POST /scraper/sessions/{id}/refresh``.
    """
    import uuid

    from sqlalchemy import select
    from temporalio.exceptions import ApplicationError

    from api.models.credential import Credential
    from api.models.scraper import ScraperSession
    from api.services.credential_service import get_secret_data
    from shared.db import AsyncSessionLocal, set_current_org

    session_id = params["session_id"]
    org_id = params["org_id"]

    # Worker path → stamp the RLS tenant GUC (scraper_sessions + credentials).
    set_current_org(org_id)
    async with AsyncSessionLocal() as db:
        session = (
            await db.execute(
                select(ScraperSession).where(
                    ScraperSession.id == uuid.UUID(session_id),
                    ScraperSession.org_id == uuid.UUID(org_id),
                )
            )
        ).scalar_one_or_none()
        if session is None:
            raise ApplicationError(f"Scraper session {session_id} not found")
        if not session.credential_id:
            raise ApplicationError(
                "Scraper session has no credential_id — cannot log in"
            )
        if not session.login_url:
            raise ApplicationError("Scraper session has no login_url — cannot log in")

        cred = (
            await db.execute(
                select(Credential).where(
                    Credential.id == session.credential_id,
                    Credential.org_id == uuid.UUID(org_id),
                )
            )
        ).scalar_one_or_none()
        if cred is None:
            raise ApplicationError("Linked credential not found")

        secret = get_secret_data(cred)
        login_url = session.login_url
        login_config = session.login_config or {}

    username = secret.get("username")
    password = secret.get("password")
    if not username or not password:
        raise ApplicationError(
            "Credential secret_data is missing 'username'/'password'"
        )

    return await login_and_capture_session(
        {
            "session_id": session_id,
            "org_id": org_id,
            "login_url": login_url,
            "username": username,
            "password": password,
            "login_config": login_config,
            # Optional TOTP/MFA seed, stored alongside username/password.
            "totp_secret": secret.get("totp_secret"),
        }
    )


async def _load_session(session_id: str, org_id: str) -> dict[str, Any] | None:
    import uuid

    from sqlalchemy import select

    from api.models.scraper import ScraperSession
    from shared.db import AsyncSessionLocal, set_current_org
    from shared.encryption import decrypt

    # Worker path → stamp the RLS tenant GUC (scraper_sessions).
    set_current_org(org_id)
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(ScraperSession).where(
                ScraperSession.id == uuid.UUID(session_id),
                ScraperSession.org_id == uuid.UUID(org_id),
            )
        )
        session = result.scalar_one_or_none()
        if session and session.session_data:
            decrypted = decrypt(session.session_data)
            return cast(dict[str, Any], json.loads(decrypted))
    return None


async def _save_session(
    session_id: str, org_id: str, storage_state: Mapping[str, Any]
) -> None:
    import uuid
    from datetime import datetime

    from sqlalchemy import select

    from api.models.scraper import ScraperSession
    from shared.db import AsyncSessionLocal, set_current_org
    from shared.encryption import encrypt

    # Worker path → stamp the RLS tenant GUC (scraper_sessions).
    set_current_org(org_id)
    encrypted = encrypt(json.dumps(storage_state))
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(ScraperSession).where(
                ScraperSession.id == uuid.UUID(session_id),
                ScraperSession.org_id == uuid.UUID(org_id),
            )
        )
        session = result.scalar_one_or_none()
        if session:
            session.session_data = encrypted
            session.last_refreshed_at = datetime.now(UTC)
            await db.commit()


async def _execute_action(page: "Page", action: dict[str, Any]) -> None:
    action_type = action.get("type", "")
    selector = action.get("selector", "")

    match action_type:
        case "click":
            await page.click(selector)
        case "fill":
            await page.fill(selector, action.get("value", ""))
        case "select":
            await page.select_option(selector, action.get("value", ""))
        case "wait":
            import asyncio

            await asyncio.sleep(action.get("seconds", 1))
        case "wait_for_selector":
            await page.wait_for_selector(selector)
        case "scroll":
            await page.evaluate(
                f"document.querySelector('{selector}')?.scrollIntoView()"
            )
