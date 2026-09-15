import time
import uuid
from collections.abc import Sequence
from typing import Annotated, Any

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

log = structlog.get_logger(__name__)

from datetime import UTC

from api.constants import (
    APPROVAL_STATUS_APPROVED,
    APPROVAL_STATUS_PENDING,
    APPROVAL_STATUS_REJECTED,
    RULE_STATUS_DRAFT,
    RULE_STATUS_PUBLISHED,
)
from api.deps import CurrentUser, get_current_user, get_smart_llm_invoke_client
from api.models.rule import Rule
from api.models.rule_approval import RuleApproval
from api.models.rule_audit import RuleAuditLog
from api.models.rule_version import RuleVersion
from api.schemas.rule import (
    AIRuleRequest,
    AIRuleResponse,
    # Gap 15: approvals
    ApprovalActionRequest,
    BatchRecordResult,
    BatchTestRequest,
    BatchTestResponse,
    # Gap 11: JS validation
    JSRuleValidateRequest,
    JSRuleValidateResponse,
    RuleAnalytics,
    RuleApprovalResponse,
    RuleAuditEntry,
    RuleCreate,
    RuleResponse,
    RuleTestRequest,
    RuleTestResponse,
    RuleTestResult,
    RuleUpdate,
    RuleVersionResponse,
)
from api.services.rule_cache import invalidate as cache_invalidate
from api.services.rule_engine import _interp, evaluate_condition_group, process_event
from shared._platform import SmartLlmInvokeClient
from shared.db import get_db

router = APIRouter(prefix="/rules", tags=["rules"])


# ─── Helpers ──────────────────────────────────────────────────────────────────


async def _get_rule_or_404(
    db: AsyncSession,
    rule_id: uuid.UUID,
    org_id: uuid.UUID,
    office_where: list[Any] | None = None,
) -> Rule:
    result = await db.execute(
        select(Rule).where(
            Rule.id == rule_id, Rule.org_id == org_id, *(office_where or [])
        )
    )
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Rule not found")
    return rule


async def _next_version_num(db: AsyncSession, rule_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.coalesce(func.max(RuleVersion.version_num), 0)).where(
            RuleVersion.rule_id == rule_id
        )
    )
    return (result.scalar() or 0) + 1


def _snapshot(rule: Rule, version_num: int, note: str | None = None) -> RuleVersion:
    return RuleVersion(
        rule_id=rule.id,
        org_id=rule.org_id,
        version_num=version_num,
        note=note,
        name=rule.name,
        description=rule.description,
        is_active=rule.is_active,
        status=rule.status,
        rule_type=rule.rule_type,
        priority=rule.priority,
        stop_on_match=rule.stop_on_match,
        trigger_events=rule.trigger_events,
        trigger_filter=rule.trigger_filter,
        conditions=rule.conditions,
        actions=rule.actions,
        else_actions=rule.else_actions,
        approval_required=rule.approval_required,
        required_approvers=rule.required_approvers,
    )


# ─── Static routes (before /{rule_id} to avoid shadowing) ─────────────────────


@router.get("", response_model=list[RuleResponse])
async def list_rules(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status: str | None = Query(
        default=None, description="Filter by status: draft | published"
    ),
) -> Sequence[Rule]:
    q = select(Rule).where(
        Rule.org_id == current.org_id, *current.office_where(Rule.office_id)
    )
    if status:
        q = q.where(Rule.status == status)
    result = await db.execute(q.order_by(Rule.priority.asc(), Rule.created_at.asc()))
    return result.scalars().all()


@router.post("", response_model=RuleResponse, status_code=201)
async def create_rule(
    body: RuleCreate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    rule = Rule(
        org_id=current.org_id, office_id=current.office_id_value, **body.model_dump()
    )
    db.add(rule)
    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.post("/test", response_model=RuleTestResponse)
async def test_rules(
    body: RuleTestRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleTestResponse:
    """Dry-run: simulate an event against all published+active rules."""
    from api.models.rule import RULE_TYPE_DECISION_TABLE
    from api.services.rule_engine import evaluate_decision_table

    result = await db.execute(
        select(Rule)
        .where(
            Rule.org_id == current.org_id,
            Rule.is_active.is_(True),
            Rule.status == RULE_STATUS_PUBLISHED,
            Rule.trigger_events.contains([body.event_type]),
        )
        .order_by(Rule.priority.asc())
    )
    rules = result.scalars().all()

    matched_rules: list[RuleTestResult] = []
    total = len(rules)

    for rule in rules:
        tf = rule.trigger_filter or {}
        if tf:
            flat = {**body.event_data, **(body.event_data.get("data", {}) or {})}
            if not all(flat.get(k) == v for k, v in tf.items()):
                continue

        if rule.rule_type == RULE_TYPE_DECISION_TABLE:
            cond_match, dt_actions = evaluate_decision_table(
                body.event_data, rule.conditions or {}
            )
            preview = [
                {
                    "type": a.get("type"),
                    "preview": {k: v for k, v in a.items() if k != "type"},
                }
                for a in dt_actions
            ]
            else_preview = []
        else:
            cond_match = evaluate_condition_group(
                body.event_data, rule.conditions or {}
            )
            preview = [
                {
                    "type": a.get("type"),
                    "preview": {
                        k: _interp(str(v), body.event_data)
                        for k, v in a.items()
                        if k != "type"
                    },
                }
                for a in (rule.actions or [])
            ]
            else_preview = [
                {
                    "type": a.get("type"),
                    "preview": {
                        k: _interp(str(v), body.event_data)
                        for k, v in a.items()
                        if k != "type"
                    },
                }
                for a in (rule.else_actions or [])
            ]

        matched_rules.append(
            RuleTestResult(
                matched=cond_match,
                rule_id=rule.id,
                rule_name=rule.name,
                rule_type=rule.rule_type,
                conditions_result=cond_match,
                actions_preview=preview if cond_match else [],
                else_actions_preview=else_preview if not cond_match else [],
                path="then" if cond_match else "else",
            )
        )

    return RuleTestResponse(
        event_type=body.event_type,
        event_data=body.event_data,
        matched_rules=[r for r in matched_rules if r.matched or r.else_actions_preview],
        total_rules_evaluated=total,
    )


@router.post("/batch", response_model=BatchTestResponse)
async def batch_evaluate(
    body: BatchTestRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BatchTestResponse:
    """
    Evaluate an array of records against all published+active rules.
    Gap 9: dry_run=False allows real action execution.
    """
    results: list[BatchRecordResult] = []

    for idx, record in enumerate(body.records):
        t_start = time.monotonic()
        matched = await process_event(
            event_type=body.event_type,
            event_data=record,
            org_id=str(current.org_id),
            db=db,
            dry_run=body.dry_run,
            correlation_id=body.correlation_id,
        )
        elapsed_ms = int((time.monotonic() - t_start) * 1000)
        results.append(
            BatchRecordResult(
                record_index=idx,
                matched_rules=[
                    {
                        "rule_id": r["rule_id"],
                        "rule_name": r["rule_name"],
                        "path": r.get("path", "then"),
                    }
                    for r in matched
                ],
                elapsed_ms=elapsed_ms,
            )
        )

    return BatchTestResponse(
        event_type=body.event_type,
        total_records=len(body.records),
        results=results,
    )


@router.get("/audit", response_model=list[RuleAuditEntry])
async def org_audit(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(default=100, ge=1, le=500),
    correlation_id: str | None = Query(default=None),  # Gap 5: filter by correlation
) -> Sequence[RuleAuditLog]:
    """Org-wide audit log — newest first."""
    q = select(RuleAuditLog).where(RuleAuditLog.org_id == current.org_id)
    if correlation_id:
        q = q.where(RuleAuditLog.correlation_id == correlation_id)
    result = await db.execute(q.order_by(RuleAuditLog.created_at.desc()).limit(limit))
    return result.scalars().all()


@router.get("/analytics", response_model=RuleAnalytics)
async def org_analytics(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleAnalytics:
    """Gap 6: org-wide rule analytics."""
    return await _compute_analytics(db, current.org_id)


@router.post("/ai-generate", response_model=AIRuleResponse)
async def ai_generate_rule(
    body: AIRuleRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    _db: Annotated[AsyncSession, Depends(get_db)],
    gate: Annotated[SmartLlmInvokeClient, Depends(get_smart_llm_invoke_client)],
) -> AIRuleResponse:
    """Gap 10: Generate a draft rule JSON from a plain-English description."""
    from fastapi import HTTPException as _HTTPException

    from api.services.ai_rule_builder import generate_rule

    # Phase F — block on monthly AI budget exhaustion. The SDK helper
    # is the one entry point: it POSTs to integration-hub which fires
    # the bell-icon alert on first trip and throttles subsequent calls,
    # then translates the 429 to HTTPException for us.
    async with gate:
        await gate.assert_budget_allowed_or_raise_http(company_id=current.org_id)

    try:
        rule_dict = await generate_rule(
            body.description,
            body.event_type,
            org_id=current.org_id,
            db=_db,
        )
    except ValueError as exc:
        # generate_rule raises ValueError on AI provider failures
        # (timeout, parse error, missing key). The underlying message
        # may include prompt fragments — funnel through a generic
        # message and log the full exc.
        log.warning(
            "ai_rule_generate_failed",
            exc_info=True,
            org_id=str(current.org_id),
            event_type=body.event_type,
        )
        raise _HTTPException(
            status_code=503,
            detail="AI rule generator unavailable; please retry.",
        ) from exc
    return AIRuleResponse(rule=rule_dict, raw_prompt=body.description)


# ─── Dynamic routes (/{rule_id} — after all static routes) ───────────────────


@router.get("/{rule_id}", response_model=RuleResponse)
async def get_rule(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    return await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )


@router.put("/{rule_id}", response_model=RuleResponse)
async def update_rule(
    rule_id: uuid.UUID,
    body: RuleUpdate,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )

    # Snapshot before applying changes (Gap 4: pass version_note)
    next_ver = await _next_version_num(db, rule_id)
    db.add(_snapshot(rule, next_ver, note=body.version_note))

    update_data = body.model_dump(exclude_none=True)
    update_data.pop("version_note", None)  # not a Rule field
    for field, val in update_data.items():
        setattr(rule, field, val)

    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.delete("/{rule_id}", status_code=204)
async def delete_rule(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    await db.delete(rule)
    await cache_invalidate(str(current.org_id))


@router.patch("/{rule_id}/priority", response_model=RuleResponse)
async def update_priority(
    rule_id: uuid.UUID,
    priority: int,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    rule.priority = priority
    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.post("/{rule_id}/publish", response_model=RuleResponse)
async def publish_rule(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    """Gap 3: Transition a rule from draft → published."""
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    rule.status = RULE_STATUS_PUBLISHED
    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.post("/{rule_id}/unpublish", response_model=RuleResponse)
async def unpublish_rule(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    """Gap 3: Transition a rule from published → draft."""
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    rule.status = RULE_STATUS_DRAFT
    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.get("/{rule_id}/versions", response_model=list[RuleVersionResponse])
async def list_versions(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=200),
) -> Sequence[RuleVersion]:
    """List historical snapshots of a rule, newest first."""
    await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    result = await db.execute(
        select(RuleVersion)
        .where(RuleVersion.rule_id == rule_id)
        .order_by(RuleVersion.version_num.desc())
        .limit(limit)
    )
    return result.scalars().all()


@router.post("/{rule_id}/versions/{version_num}/restore", response_model=RuleResponse)
async def restore_version(
    rule_id: uuid.UUID,
    version_num: int,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Rule:
    """Restore a rule to a historical snapshot. Snapshots current state first."""
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )

    snap_res = await db.execute(
        select(RuleVersion).where(
            RuleVersion.rule_id == rule_id,
            RuleVersion.version_num == version_num,
        )
    )
    snap = snap_res.scalar_one_or_none()
    if not snap:
        raise HTTPException(status_code=404, detail=f"Version {version_num} not found")

    next_ver = await _next_version_num(db, rule_id)
    db.add(
        _snapshot(
            rule, next_ver, note=f"Pre-restore snapshot (restoring to v{version_num})"
        )
    )

    for field in (
        "name",
        "description",
        "is_active",
        "status",
        "rule_type",
        "priority",
        "stop_on_match",
        "trigger_events",
        "trigger_filter",
        "conditions",
        "actions",
        "else_actions",
    ):
        setattr(rule, field, getattr(snap, field))

    await db.flush()
    await cache_invalidate(str(current.org_id))
    return rule


@router.get("/{rule_id}/audit", response_model=list[RuleAuditEntry])
async def rule_audit(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    limit: int = Query(default=50, ge=1, le=500),
    correlation_id: str | None = Query(default=None),  # Gap 5
) -> Sequence[RuleAuditLog]:
    """Audit log for a specific rule — newest first."""
    await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    q = select(RuleAuditLog).where(
        RuleAuditLog.rule_id == rule_id,
        RuleAuditLog.org_id == current.org_id,
    )
    if correlation_id:
        q = q.where(RuleAuditLog.correlation_id == correlation_id)
    result = await db.execute(q.order_by(RuleAuditLog.created_at.desc()).limit(limit))
    return result.scalars().all()


@router.get("/{rule_id}/analytics", response_model=RuleAnalytics)
async def rule_analytics(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleAnalytics:
    """Gap 6: per-rule analytics."""
    await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    return await _compute_analytics(db, current.org_id, rule_id=rule_id)


# ─── Gap 11: JavaScript rule validation ──────────────────────────────────────


@router.post("/validate-js", response_model=JSRuleValidateResponse)
async def validate_js(
    body: JSRuleValidateRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    _db: Annotated[AsyncSession, Depends(get_db)],
) -> JSRuleValidateResponse:
    """Quick syntax check for JavaScript rule code."""
    from api.services.js_engine import validate_js_syntax

    error = validate_js_syntax(body.code)
    return JSRuleValidateResponse(valid=error is None, error=error)


# ─── Gap 13: Client SDK downloads ─────────────────────────────────────────────


@router.get("/sdks/{language}")
async def download_sdk(
    language: str,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    _db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    """Download the client SDK for the given language (python | javascript | java)."""

    # pre-existing bug fixed: shared.config exposes no `settings` singleton (only Settings/get_settings), so the old import raised ImportError when this endpoint was hit
    from shared.config import get_settings

    settings = get_settings()
    base_url = getattr(settings, "public_base_url", "http://localhost:8000")

    sdks: dict[str, tuple[str, str, str]] = {
        "python": ("mit_stack_rules.py", "text/x-python", _python_sdk(base_url)),
        "javascript": ("mitStackRules.js", "application/javascript", _js_sdk(base_url)),
        "java": ("MitStackRulesClient.java", "text/x-java", _java_sdk(base_url)),
    }

    if language not in sdks:
        raise HTTPException(
            status_code=404,
            detail=f"SDK language '{language}' not available. Choose: python, javascript, java",
        )

    filename, content_type, content = sdks[language]

    return Response(
        content=content,
        media_type=content_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _python_sdk(base_url: str) -> str:
    return f'''"""
Mit Stack Rules — Python Client SDK
Generated by: {base_url}

Usage:
    client = MitStackRulesClient(base_url="{base_url}", token="your-jwt-token")
    results = client.process_event("form_submit", {{"email": "user@example.com"}})
    for result in results:
        print(result["rule_name"], result["matched"])
"""
import httpx
from typing import Any


class MitStackRulesClient:
    def __init__(self, base_url: str = "{base_url}", token: str = ""):
        self.base_url = base_url.rstrip("/")
        self._headers = {{"Authorization": f"Bearer {{token}}", "Content-Type": "application/json"}}

    def _url(self, path: str) -> str:
        return f"{{self.base_url}}{{path}}"

    def process_event(
        self, event_type: str, event_data: dict[str, Any],
        dry_run: bool = False, correlation_id: str | None = None
    ) -> list[dict[str, Any]]:
        """Evaluate all active rules for event_type against event_data."""
        payload = {{"event_type": event_type, "event_data": event_data, "dry_run": dry_run}}
        if correlation_id:
            payload["correlation_id"] = correlation_id
        with httpx.Client() as client:
            resp = client.post(self._url("/rules/test"), json=payload, headers=self._headers)
            resp.raise_for_status()
            return resp.json().get("matched_rules", [])

    def batch_evaluate(
        self, event_type: str, records: list[dict[str, Any]], dry_run: bool = True
    ) -> list[dict[str, Any]]:
        """Evaluate an array of records. Returns per-record results."""
        payload = {{"event_type": event_type, "records": records, "dry_run": dry_run}}
        with httpx.Client() as client:
            resp = client.post(self._url("/rules/batch"), json=payload, headers=self._headers)
            resp.raise_for_status()
            return resp.json().get("results", [])

    def list_rules(self, status: str | None = None) -> list[dict[str, Any]]:
        params = {{"status": status}} if status else {{}}
        with httpx.Client() as client:
            resp = client.get(self._url("/rules"), params=params, headers=self._headers)
            resp.raise_for_status()
            return resp.json()

    def get_audit_log(self, rule_id: str | None = None, limit: int = 50) -> list[dict[str, Any]]:
        path = f"/rules/{{rule_id}}/audit" if rule_id else "/rules/audit"
        with httpx.Client() as client:
            resp = client.get(self._url(path), params={{"limit": limit}}, headers=self._headers)
            resp.raise_for_status()
            return resp.json()
'''


def _js_sdk(base_url: str) -> str:
    return f"""/**
 * Mit Stack Rules — JavaScript/TypeScript Client SDK
 * Base URL: {base_url}
 *
 * Usage (Node.js / browser):
 *   const client = new MitStackRulesClient('{base_url}', 'your-jwt-token');
 *   const results = await client.processEvent('form_submit', {{ email: 'user@example.com' }});
 */

export class MitStackRulesClient {{
  constructor(baseUrl = '{base_url}', token = '') {{
    this.baseUrl = baseUrl.replace(/\\/$/, '');
    this.token = token;
  }}

  get _headers() {{
    return {{
      'Authorization': `Bearer ${{this.token}}`,
      'Content-Type': 'application/json',
    }};
  }}

  async _request(method, path, body = null) {{
    const resp = await fetch(`${{this.baseUrl}}${{path}}`, {{
      method,
      headers: this._headers,
      body: body ? JSON.stringify(body) : undefined,
    }});
    if (!resp.ok) throw new Error(`${{method}} ${{path}} → ${{resp.status}}: ${{await resp.text()}}`);
    return resp.json();
  }}

  /** Evaluate all active rules for event_type against event_data. */
  async processEvent(eventType, eventData, {{ dryRun = false, correlationId = null }} = {{}}) {{
    const payload = {{ event_type: eventType, event_data: eventData, dry_run: dryRun }};
    if (correlationId) payload.correlation_id = correlationId;
    const result = await this._request('POST', '/rules/test', payload);
    return result.matched_rules || [];
  }}

  /** Evaluate an array of records. Returns per-record results. */
  async batchEvaluate(eventType, records, dryRun = true) {{
    const result = await this._request('POST', '/rules/batch', {{
      event_type: eventType, records, dry_run: dryRun,
    }});
    return result.results || [];
  }}

  /** List all rules. */
  async listRules(status = null) {{
    const q = status ? `?status=${{status}}` : '';
    return this._request('GET', `/rules${{q}}`);
  }}

  /** Get audit log (optionally scoped to a single rule). */
  async getAuditLog(ruleId = null, limit = 50) {{
    const path = ruleId ? `/rules/${{ruleId}}/audit` : '/rules/audit';
    return this._request('GET', `${{path}}?limit=${{limit}}`);
  }}

  /** Execute a rule flow pipeline. */
  async executeFlow(flowId, eventType, eventData, dryRun = true) {{
    return this._request('POST', `/rule-flows/${{flowId}}/execute`, {{
      event_type: eventType, event_data: eventData, dry_run: dryRun,
    }});
  }}
}}
"""


def _java_sdk(base_url: str) -> str:
    return f'''package io.mitstack.rules;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.List;
import java.util.Map;

/**
 * Mit Stack Rules — Java Client SDK
 * Base URL: {base_url}
 *
 * Usage:
 *   MitStackRulesClient client = new MitStackRulesClient("{base_url}", "your-jwt-token");
 *   String result = client.processEvent("form_submit", "{{\\\"email\\\":\\\"user@example.com\\\"}}");
 *
 * Requires Java 11+ (java.net.http.HttpClient).
 * Add a JSON library (Jackson, Gson) for object serialization.
 */
public class MitStackRulesClient {{

    private final String baseUrl;
    private final String token;
    private final HttpClient http;

    public MitStackRulesClient(String baseUrl, String token) {{
        this.baseUrl = baseUrl.replaceAll("/$", "");
        this.token = token;
        this.http = HttpClient.newHttpClient();
    }}

    private HttpRequest.Builder requestBuilder(String path) {{
        return HttpRequest.newBuilder()
            .uri(URI.create(baseUrl + path))
            .header("Authorization", "Bearer " + token)
            .header("Content-Type", "application/json");
    }}

    /**
     * Evaluate all active rules for event_type against event_data JSON string.
     * Returns the raw JSON response body.
     */
    public String processEvent(String eventType, String eventDataJson) throws Exception {{
        String body = String.format(
            "{{\\\"event_type\\\":\\"%s\\\",\\\"event_data\\\":%s,\\\"dry_run\\\":false}}",
            eventType, eventDataJson
        );
        HttpRequest request = requestBuilder("/rules/test")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() >= 400) {{
            throw new RuntimeException("API error " + response.statusCode() + ": " + response.body());
        }}
        return response.body();
    }}

    /**
     * Batch evaluate. Returns raw JSON response body.
     */
    public String batchEvaluate(String eventType, String recordsJson) throws Exception {{
        String body = String.format(
            "{{\\\"event_type\\\":\\"%s\\\",\\\"records\\\":%s,\\\"dry_run\\\":true}}",
            eventType, recordsJson
        );
        HttpRequest request = requestBuilder("/rules/batch")
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() >= 400) {{
            throw new RuntimeException("API error " + response.statusCode() + ": " + response.body());
        }}
        return response.body();
    }}

    /**
     * Get audit log. Returns raw JSON response body.
     */
    public String getAuditLog(String ruleId, int limit) throws Exception {{
        String path = ruleId != null
            ? "/rules/" + ruleId + "/audit?limit=" + limit
            : "/rules/audit?limit=" + limit;
        HttpRequest request = requestBuilder(path).GET().build();
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        return response.body();
    }}
}}
'''


# ─── Gap 15: Rule approval endpoints ─────────────────────────────────────────


@router.post("/{rule_id}/request-approval", response_model=RuleApprovalResponse)
async def request_approval(
    rule_id: uuid.UUID,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleApproval:
    """
    Request approval to publish a rule.
    Creates a RuleApproval with status=pending.
    The rule must have approval_required=True and at least one required_approver.
    """
    rule = await _get_rule_or_404(
        db, rule_id, current.org_id, current.office_where(Rule.office_id)
    )
    if not rule.approval_required:
        raise HTTPException(
            status_code=400,
            detail="Rule does not require approval. Set approval_required=true first.",
        )
    if not rule.required_approvers:
        raise HTTPException(
            status_code=400, detail="No required_approvers set on this rule."
        )

    # Cancel any existing pending approvals for this rule
    await db.execute(
        select(RuleApproval)  # we just check, then update via ORM
    )
    pending_res = await db.execute(
        select(RuleApproval).where(
            RuleApproval.rule_id == rule_id,
            RuleApproval.status == APPROVAL_STATUS_PENDING,
        )
    )
    existing = pending_res.scalars().all()
    for old in existing:
        old.status = APPROVAL_STATUS_REJECTED
        old.rejection_note = "Superseded by a new approval request"

    # Snapshot the current rule state
    snapshot = {
        "name": rule.name,
        "rule_type": rule.rule_type,
        "conditions": rule.conditions,
        "actions": rule.actions,
        "else_actions": rule.else_actions,
        "trigger_events": rule.trigger_events,
    }

    approval = RuleApproval(
        rule_id=rule_id,
        org_id=current.org_id,
        requested_by=current.email
        if hasattr(current, "email")
        else str(current.user_id),
        required_approvers=rule.required_approvers,
        approvals=[],
        rule_snapshot=snapshot,
        status=APPROVAL_STATUS_PENDING,
    )
    db.add(approval)
    await db.flush()
    return approval


@router.get("/approvals", response_model=list[RuleApprovalResponse])
async def list_approvals(
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    status: str | None = Query(default=None),
) -> Sequence[RuleApproval]:
    """List rule approvals for the org. Filter by status=pending|approved|rejected."""
    q = select(RuleApproval).where(RuleApproval.org_id == current.org_id)
    if status:
        q = q.where(RuleApproval.status == status)
    result = await db.execute(q.order_by(RuleApproval.created_at.desc()))
    return result.scalars().all()


@router.post("/approvals/{approval_id}/decide", response_model=RuleApprovalResponse)
async def decide_approval(
    approval_id: uuid.UUID,
    body: ApprovalActionRequest,
    current: Annotated[CurrentUser, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> RuleApproval:
    """
    Approve or reject a pending rule approval.
    The calling user's email is recorded as the approver.

    When the last required approver approves → rule is auto-published.
    Any rejection immediately sets status=rejected.
    """
    from datetime import datetime

    res = await db.execute(
        select(RuleApproval).where(
            RuleApproval.id == approval_id,
            RuleApproval.org_id == current.org_id,
        )
    )
    approval = res.scalar_one_or_none()
    if not approval:
        raise HTTPException(status_code=404, detail="Approval not found")
    if approval.status != APPROVAL_STATUS_PENDING:
        raise HTTPException(
            status_code=400, detail=f"Approval is already {approval.status}"
        )

    approver_email = (
        current.email if hasattr(current, "email") else str(current.user_id)
    )

    if body.action == "reject":
        approval.status = APPROVAL_STATUS_REJECTED
        approval.rejection_note = body.note
        approval.resolved_at = datetime.now(UTC)
    elif body.action == "approve":
        # Add this approval if not already recorded
        current_approvals = list(approval.approvals or [])
        already_approved = any(
            a.get("email") == approver_email for a in current_approvals
        )
        if not already_approved:
            current_approvals.append(
                {
                    "email": approver_email,
                    "approved_at": datetime.now(UTC).isoformat(),
                    "note": body.note or "",
                }
            )
            approval.approvals = current_approvals

        # Check if all required approvers have approved
        approved_emails = {a["email"] for a in current_approvals}
        required = set(approval.required_approvers or [])
        if required.issubset(approved_emails):
            approval.status = APPROVAL_STATUS_APPROVED
            approval.resolved_at = datetime.now(UTC)
            # Auto-publish the rule
            rule_res = await db.execute(
                select(Rule).where(
                    Rule.id == approval.rule_id,
                    Rule.org_id == current.org_id,
                )
            )
            rule = rule_res.scalar_one_or_none()
            if rule:
                rule.status = RULE_STATUS_PUBLISHED
                from api.services.rule_cache import invalidate as cache_invalidate

                await cache_invalidate(str(current.org_id))
    else:
        raise HTTPException(
            status_code=400, detail="action must be 'approve' or 'reject'"
        )

    await db.flush()
    return approval


# ─── Analytics helper ─────────────────────────────────────────────────────────


async def _compute_analytics(
    db: AsyncSession,
    org_id: uuid.UUID,
    rule_id: uuid.UUID | None = None,
) -> RuleAnalytics:
    """Gap 6: compute aggregate stats from rule_audit_log."""
    base_where = [RuleAuditLog.org_id == org_id]
    if rule_id:
        base_where.append(RuleAuditLog.rule_id == rule_id)

    # Aggregate query
    agg = await db.execute(
        select(
            func.count().label("total"),
            func.sum(func.cast(RuleAuditLog.matched, type_=func.count().type)).label(
                "matched"
            ),
            func.avg(RuleAuditLog.elapsed_ms).label("avg_ms"),
            func.min(RuleAuditLog.elapsed_ms).label("min_ms"),
            func.max(RuleAuditLog.elapsed_ms).label("max_ms"),
        ).where(*base_where)
    )
    row = agg.one()
    total = row.total or 0
    match_count = int(row.matched or 0)

    # Top event types
    et_result = await db.execute(
        select(RuleAuditLog.event_type, func.count().label("cnt"))
        .where(*base_where)
        .group_by(RuleAuditLog.event_type)
        .order_by(func.count().desc())
        .limit(10)
    )
    top_event_types = {r.event_type: r.cnt for r in et_result}

    return RuleAnalytics(
        total_evaluations=total,
        match_count=match_count,
        no_match_count=total - match_count,
        match_rate_pct=round(match_count / total * 100, 1) if total else 0.0,
        avg_elapsed_ms=round(float(row.avg_ms), 2) if row.avg_ms is not None else None,
        min_elapsed_ms=row.min_ms,
        max_elapsed_ms=row.max_ms,
        top_event_types=top_event_types,
    )
