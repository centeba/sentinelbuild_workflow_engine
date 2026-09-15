"""Main Temporal workflow that executes a node DAG.

New in this version:
  - Branch-aware edge routing (true/false/success/error/switch_* edges)
  - Per-node error catching with continue_on_error + error-edge routing
  - if_condition node: sets node_status to "true_branch" or "false_branch"
  - switch node: evaluates expression against cases, routes switch_{label} edges
  - for_each node: iterates over an array and runs body_nodes mini-DAG per item
  - merge node: rejoins parallel branches (merge / append / first / last modes)
"""

import json
import re
from collections import deque
from dataclasses import dataclass
from datetime import timedelta
from typing import Any, cast

from temporalio import workflow
from temporalio.common import RetryPolicy

# Child workflow for the durable autonomous agent run (agentic:true agent_node).
from temporal.workflows.agent_run_workflow import AgentRunParams, AgentRunWorkflow

with workflow.unsafe.imports_passed_through():
    from temporal.activities.action_activity import ActionParams, run_action_node
    from temporal.activities.agent_activity import AgentParams, run_agent_node
    from temporal.activities.agent_graph_activity import (
        AgentGraphParams,
        run_agent_graph_node,
    )
    from temporal.activities.approval_activity import (
        RegisterApprovalTokenParams,
        SendApprovalEmailParams,
        register_approval_token,
        send_approval_email,
    )
    from temporal.activities.call_workflow_activity import (
        CallSubWorkflowParams,
        call_sub_workflow,
    )
    from temporal.activities.code_activity import CodeParams, run_code
    from temporal.activities.condition_activity import (
        ConditionParams,
        evaluate_condition,
    )
    from temporal.activities.db_activity import DbQueryParams, run_db_query
    from temporal.activities.domain_condition_activity import (
        DomainConditionParams,
        evaluate_domain_condition,
    )
    from temporal.activities.email_activity import EmailParams, send_email
    from temporal.activities.http_activity import HttpParams, http_request
    from temporal.activities.integration_hub_activity import (
        IntegrationHubParams,
        call_integration_hub,
    )
    from temporal.activities.llm_activity import LLMParams, run_llm
    from temporal.activities.notify_activity import (
        NotifyWorkflowEventParams,
        notify_workflow_event,
    )
    from temporal.activities.pack_action_activity import (
        PackActionParams,
        dispatch_pack_action,
    )
    from temporal.activities.rule_engine_activity import (
        EvaluateRulesParams,
        evaluate_rules,
    )
    from temporal.activities.state_activity import (
        LogEventParams,
        NodeExecutionUpdate,
        UpdateExecutionParams,
        emit_log_event,
        update_execution_status,
        update_node_execution,
    )
    from temporal.activities.transform_activity import TransformParams, transform_data


@dataclass
class WorkflowExecutorParams:
    execution_id: str
    workflow_id: str
    org_id: str
    input_data: dict[str, Any]
    version_id: str | None = None


@dataclass
class WorkflowResult:
    status: str
    output_data: dict[str, Any]
    error: str | None = None


DEFAULT_RETRY = RetryPolicy(maximum_attempts=3, initial_interval=timedelta(seconds=2))
NO_RETRY = RetryPolicy(maximum_attempts=1)

# ── Inline control-flow node types (handled in main loop, not via _execute_node)
_CONTROL_FLOW_TYPES = {
    "if_condition",
    "domain_condition",
    "switch",
    "for_each",
    "merge",
}


def _describe_failure(
    exc: BaseException, node_id: str | None, node_type: str | None
) -> str:
    """Build a human-readable failure reason from a (possibly Temporal-wrapped)
    exception, naming the node that failed.

    Temporal wraps an activity failure as ``ActivityError -> ApplicationError``,
    whose outer ``str()`` is just ``"Activity task failed"`` — useless on the
    dashboard. We unwrap to the innermost cause for the real reason (the actual
    error a node's activity raised) and prefix it with which step failed, so
    "Recent Activity" can show e.g.::

        Step 'notify_target' (pack_action) failed: 404 Not Found — project ...

    Pure/deterministic (no I/O) so it's safe to call inside the workflow.
    """
    seen: set[int] = set()
    cur: BaseException | None = exc
    deepest: BaseException = exc
    while cur is not None and id(cur) not in seen:
        seen.add(id(cur))
        deepest = cur
        # Temporal failures expose the wrapped cause via ``.cause``; plain
        # exceptions chain via ``__cause__``. Prefer whichever is present.
        nxt = getattr(cur, "cause", None)
        if not isinstance(nxt, BaseException):
            nxt = cur.__cause__
        cur = nxt if isinstance(nxt, BaseException) else None

    reason = str(deepest).strip() or type(deepest).__name__
    if node_id:
        where = f"Step '{node_id}'" + (f" ({node_type})" if node_type else "")
        return f"{where} failed: {reason}"
    return reason


def _cross_company_action_allowed(
    rule: dict[str, Any] | None, participants: list[dict[str, Any]], exec_org_id: str
) -> bool:
    """A5 federation gate — pure/deterministic (safe inside a Temporal workflow).

    A node with no rule, no target company, or whose target IS the executing
    company runs normally. A node targeting ANOTHER company runs only if the
    executing company is an authorized participant (role owner/executor) or is
    explicitly listed in the rule's ``authorized_companies``.
    """
    if not rule:
        return True
    target = rule.get("target_company_id")
    if not target or str(target) == str(exec_org_id):
        return True
    allowed = {str(c) for c in (rule.get("authorized_companies") or [])}
    for p in participants or []:
        if str(p.get("company_id")) == str(exec_org_id) and p.get("role") in (
            "owner",
            "executor",
            "action_executor",
        ):
            allowed.add(str(exec_org_id))
    return str(exec_org_id) in allowed


@workflow.defn
class WorkflowExecutor:
    """Executes a workflow DAG by running each node as a Temporal activity."""

    def __init__(self) -> None:
        # Signal state for wait_approval node
        self._approval_status: str | None = None  # "approved" | "rejected"
        self._approval_note: str = ""

    @workflow.signal
    async def approval_signal(self, action: str, note: str = "") -> None:
        """
        Signal sent by the API when an approver clicks Approve or Reject.
        action: "approved" | "rejected"
        """
        self._approval_status = action
        self._approval_note = note

    @workflow.run
    async def run(self, params: WorkflowExecutorParams) -> WorkflowResult:
        # 1. Load workflow definition (from published version if available)
        wf_def_json = await workflow.execute_activity(
            "load_workflow_definition",
            {
                "workflow_id": params.workflow_id,
                "org_id": params.org_id,
                "version_id": params.version_id,
            },
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=DEFAULT_RETRY,
        )
        definition: dict[str, Any] = json.loads(wf_def_json)
        nodes: list[dict[str, Any]] = definition.get("nodes", [])
        edges: list[dict[str, Any]] = definition.get("edges", [])
        workflow_name: str = definition.get("name", params.workflow_id)
        # A5 federation governance (merged in by load_workflow_definition).
        participants: list[dict[str, Any]] = definition.get("participants", []) or []
        action_authz_rules: dict[str, Any] = (
            definition.get("action_authz_rules", {}) or {}
        )

        # 2. Mark execution as running
        await workflow.execute_activity(
            update_execution_status,
            UpdateExecutionParams(
                execution_id=params.execution_id,
                status="running",
            ),
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=DEFAULT_RETRY,
        )

        # 3. Build adjacency maps
        children: dict[str, list[str]] = {n["id"]: [] for n in nodes}
        parents: dict[str, list[str]] = {n["id"]: [] for n in nodes}
        # edge_branches[(from_id, to_id)] = branch label or None (unconditional)
        edge_branches: dict[tuple[str, str], str | None] = {}

        for edge in edges:
            frm, to = edge.get("from"), edge.get("to")
            # Skip malformed edges: missing an endpoint, or referencing a node
            # id that isn't in the graph. A corrupt/partial workflow definition
            # must not crash the whole execution (it would poison-loop on every
            # Temporal retry). Drop the bad edge and keep executing the rest.
            if not frm or not to or frm not in children or to not in parents:
                workflow.logger.warning("skipping malformed workflow edge: %r", edge)
                continue
            children[frm].append(to)
            parents[to].append(frm)
            edge_branches[(frm, to)] = edge.get("branch") or None

        # 4. Topological sort (Kahn's algorithm)
        ordered = _topological_sort(nodes, children)

        # 5. Execute nodes in topological order
        node_outputs: dict[str, Any] = {}
        # node_status values: "success", "error", "skipped",
        #                     "true_branch", "false_branch", "switch_{label}"
        node_status: dict[str, str] = {}
        node_map = {n["id"]: n for n in nodes}
        final_output: dict[str, Any] = {}
        # Track the node currently executing so a failure can be attributed to
        # it in the execution-level error_message (surfaced on the dashboard).
        failed_node_id: str | None = None
        failed_node_type: str | None = None

        try:
            for node_id in ordered:
                node = node_map[node_id]
                node_type = node["type"]
                config = node.get("config", {})
                failed_node_id, failed_node_type = node_id, node_type

                # Trigger nodes: they already fired — pass through input
                if node_type.endswith("_trigger"):
                    node_status[node_id] = "success"
                    node_outputs[node_id] = params.input_data
                    continue

                # Skip check: if all parent edges are "dead", skip this node
                parent_ids = parents.get(node_id, [])
                if parent_ids and not _should_execute_node(
                    node_id, parent_ids, edge_branches, node_status
                ):
                    node_status[node_id] = "skipped"
                    node_outputs[node_id] = {}
                    await _record_node_done(
                        params.execution_id, node_id, node_type, {}, None, "skipped"
                    )
                    continue

                # Build input from live parent outputs (or workflow input if root)
                node_input = _build_node_input(
                    node_id,
                    parent_ids,
                    edge_branches,
                    node_status,
                    node_outputs,
                    params.input_data,
                )

                await _record_node_start(
                    params.execution_id, node_id, node_type, node_input
                )

                # ── A5 cross-company federation gate ───────────────────────────
                # Deny (skip) a node that acts on another company's behalf unless
                # the executing company is an authorized participant. Deterministic
                # (no external call) so it's safe inside the workflow.
                _rule = action_authz_rules.get(node_id)
                if _rule and not _cross_company_action_allowed(
                    _rule, participants, params.org_id
                ):
                    workflow.logger.warning(
                        "cross-company action denied: node=%s exec_org=%s target=%s",
                        node_id,
                        params.org_id,
                        _rule.get("target_company_id"),
                    )
                    node_status[node_id] = "skipped"
                    node_outputs[node_id] = {
                        "denied": True,
                        "reason": "cross_company_not_authorized",
                        "target_company_id": _rule.get("target_company_id"),
                    }
                    await _record_node_done(
                        params.execution_id,
                        node_id,
                        node_type,
                        node_outputs[node_id],
                        None,
                        "skipped",
                    )
                    continue

                # ── Control-flow nodes (inline, no activity dispatch) ──────────

                if node_type == "if_condition":
                    try:
                        matched = await workflow.execute_activity(
                            evaluate_condition,
                            ConditionParams(
                                input_data=node_input,
                                expression=config.get("expression", "true"),
                            ),
                            start_to_close_timeout=timedelta(seconds=10),
                            retry_policy=NO_RETRY,
                        )
                        output = {"matched": matched, **node_input}
                        status = "true_branch" if matched else "false_branch"
                        node_status[node_id] = status
                        node_outputs[node_id] = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            status,
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                    continue

                if node_type == "domain_condition":
                    # No-code branch on live domain data: fetch the referenced
                    # entities (project + sub-entities) and evaluate the
                    # structured condition group. Routes true_branch/false_branch
                    # exactly like if_condition.
                    try:
                        project_id = _interpolate(
                            str(config.get("project_id", "{{trigger.project_id}}")),
                            node_input,
                        )
                        matched = await workflow.execute_activity(
                            evaluate_domain_condition,
                            DomainConditionParams(
                                conditions=config.get("conditions") or {},
                                project_id=project_id,
                                org_id=params.org_id,
                            ),
                            start_to_close_timeout=timedelta(seconds=20),
                            retry_policy=NO_RETRY,
                        )
                        output = {"matched": matched, **node_input}
                        status = "true_branch" if matched else "false_branch"
                        node_status[node_id] = status
                        node_outputs[node_id] = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            status,
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                    continue

                if node_type == "switch":
                    try:
                        # Resolve the switch expression value
                        raw = _interpolate(config.get("expression", ""), node_input)
                        matched_label = config.get("default_case", "default")
                        for case in config.get("cases", []):
                            if str(raw) == str(case.get("value", "")):
                                matched_label = case.get("label") or case["value"]
                                break
                        output = {
                            "switch_value": raw,
                            "matched_case": matched_label,
                            **node_input,
                        }
                        status = f"switch_{matched_label}"
                        node_status[node_id] = status
                        node_outputs[node_id] = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            status,
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                    continue

                if node_type == "for_each":
                    try:
                        items_path = config.get("items_path", "items")
                        items = _get_nested(node_input, items_path)
                        if not isinstance(items, list):
                            items = []
                        results = []
                        for idx, item in enumerate(items):
                            item_input = {**node_input, "item": item, "_index": idx}
                            item_out = await self._run_for_each_body(
                                config, item_input, params
                            )
                            results.append(item_out)
                        output = {"results": results, "count": len(results)}
                        node_status[node_id] = "success"
                        node_outputs[node_id] = output
                        final_output = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            "success",
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                        if node_status.get(node_id) == "error" and not (
                            config.get("continue_on_error")
                            or _has_error_edges(node_id, children, edge_branches)
                        ):
                            raise
                    continue

                if node_type == "wait_approval":
                    try:
                        import uuid as _uuid_mod

                        approval_token = str(_uuid_mod.uuid4())
                        timeout_hours = int(config.get("timeout_hours", 72))

                        # Persist token + send email
                        await workflow.execute_activity(
                            register_approval_token,
                            RegisterApprovalTokenParams(
                                execution_id=params.execution_id,
                                approval_token=approval_token,
                                node_id=node_id,
                                approver_email=_interpolate(
                                    config.get("approver_email", ""), node_input
                                ),
                                timeout_hours=timeout_hours,
                            ),
                            start_to_close_timeout=timedelta(seconds=30),
                            retry_policy=DEFAULT_RETRY,
                        )
                        await workflow.execute_activity(
                            send_approval_email,
                            SendApprovalEmailParams(
                                execution_id=params.execution_id,
                                approval_token=approval_token,
                                approver_email=_interpolate(
                                    config.get("approver_email", ""), node_input
                                ),
                                prompt=_interpolate(
                                    config.get("prompt", "Please review and approve."),
                                    node_input,
                                ),
                                workflow_name=workflow_name,
                                node_label=config.get("label", "Approval Required"),
                                timeout_hours=timeout_hours,
                            ),
                            start_to_close_timeout=timedelta(seconds=30),
                            retry_policy=NO_RETRY,
                        )

                        # Wait for the signal (blocks until approved/rejected or timeout)
                        try:
                            await workflow.wait_condition(
                                lambda: self._approval_status is not None,
                                timeout=timedelta(hours=timeout_hours),
                            )
                            act = self._approval_status
                            note = self._approval_note
                        except Exception:
                            act = "timeout"
                            note = ""

                        output = {
                            "approval": act,
                            "approval_note": note,
                            **node_input,
                        }
                        # Route: approved → true_branch, rejected/timeout → false_branch
                        status = "true_branch" if act == "approved" else "false_branch"
                        node_status[node_id] = status
                        node_outputs[node_id] = output
                        final_output = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            status,
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                    continue

                if node_type == "call_workflow":
                    try:
                        output = await workflow.execute_activity(
                            call_sub_workflow,
                            CallSubWorkflowParams(
                                parent_execution_id=params.execution_id,
                                sub_workflow_id=config["sub_workflow_id"],
                                org_id=params.org_id,
                                node_id=node_id,
                                input_data=node_input,
                                timeout_hours=int(config.get("timeout_hours", 24)),
                            ),
                            start_to_close_timeout=timedelta(
                                hours=int(config.get("timeout_hours", 24)) + 1
                            ),
                            retry_policy=NO_RETRY,
                            heartbeat_timeout=timedelta(minutes=2),
                        )
                        node_status[node_id] = "success"
                        node_outputs[node_id] = output
                        final_output = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            "success",
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                        if node_status.get(node_id) == "error" and not (
                            config.get("continue_on_error")
                            or _has_error_edges(node_id, children, edge_branches)
                        ):
                            raise
                    continue

                if node_type == "merge":
                    try:
                        output = _merge_parent_outputs(
                            node_id,
                            parent_ids,
                            edge_branches,
                            node_status,
                            node_outputs,
                            config,
                        )
                        node_status[node_id] = "success"
                        node_outputs[node_id] = output
                        final_output = output
                        await _record_node_done(
                            params.execution_id,
                            node_id,
                            node_type,
                            output,
                            None,
                            "success",
                        )
                    except Exception as exc:
                        await self._handle_node_error(
                            exc,
                            node_id,
                            node_type,
                            config,
                            children,
                            edge_branches,
                            node_status,
                            node_outputs,
                            params,
                        )
                    continue

                # ── Regular activity nodes ────────────────────────────────────
                try:
                    output = await self._execute_node(
                        node_id, node_type, config, node_input, params
                    )
                    node_status[node_id] = "success"
                    node_outputs[node_id] = output
                    final_output = output
                    await _record_node_done(
                        params.execution_id, node_id, node_type, output, None, "success"
                    )
                except Exception as exc:
                    await self._handle_node_error(
                        exc,
                        node_id,
                        node_type,
                        config,
                        children,
                        edge_branches,
                        node_status,
                        node_outputs,
                        params,
                    )
                    # Re-raise only if there are no error edges and continue_on_error is off
                    if node_status.get(node_id) == "error" and not (
                        config.get("continue_on_error")
                        or _has_error_edges(node_id, children, edge_branches)
                    ):
                        raise

            # All nodes ran — clear node attribution so a failure in the
            # completion/notify steps below isn't blamed on the last node.
            failed_node_id, failed_node_type = None, None

            # 6. Mark execution complete
            await workflow.execute_activity(
                update_execution_status,
                UpdateExecutionParams(
                    execution_id=params.execution_id,
                    status="completed",
                    output_data=final_output,
                ),
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=DEFAULT_RETRY,
            )

            # 7. Notify on completion if the workflow definition opts in
            notify_cfg = definition.get("notify_on_completion", {})
            if notify_cfg:
                await workflow.execute_activity(
                    notify_workflow_event,
                    NotifyWorkflowEventParams(
                        execution_id=params.execution_id,
                        workflow_id=params.workflow_id,
                        org_id=params.org_id,
                        workflow_name=workflow_name,
                        event="completed",
                        trigger_type=definition.get("trigger_type", "manual"),
                        notify_channels=notify_cfg.get("channels", []),
                        notify_recipients=notify_cfg.get("recipients", []),
                        notify_webhook_url=notify_cfg.get("webhook_url"),
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=NO_RETRY,
                )

            return WorkflowResult(status="completed", output_data=final_output)

        except Exception as exc:
            # Unwrap Temporal's "Activity task failed" wrapper to the real root
            # cause and name the failing node, so Recent Activity shows what
            # actually went wrong instead of a generic message.
            error_msg = _describe_failure(exc, failed_node_id, failed_node_type)
            await workflow.execute_activity(
                update_execution_status,
                UpdateExecutionParams(
                    execution_id=params.execution_id,
                    status="failed",
                    error_message=error_msg,
                ),
                start_to_close_timeout=timedelta(seconds=10),
                retry_policy=NO_RETRY,
            )

            # Notify on failure if the workflow definition opts in
            notify_cfg = definition.get("notify_on_failure", {})
            if notify_cfg:
                await workflow.execute_activity(
                    notify_workflow_event,
                    NotifyWorkflowEventParams(
                        execution_id=params.execution_id,
                        workflow_id=params.workflow_id,
                        org_id=params.org_id,
                        workflow_name=workflow_name,
                        event="failed",
                        error_message=error_msg,
                        trigger_type=definition.get("trigger_type", "manual"),
                        notify_channels=notify_cfg.get("channels", []),
                        notify_recipients=notify_cfg.get("recipients", []),
                        notify_webhook_url=notify_cfg.get("webhook_url"),
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=NO_RETRY,
                )

            return WorkflowResult(status="failed", output_data={}, error=error_msg)

    # ── Node error handler ────────────────────────────────────────────────────

    async def _handle_node_error(
        self,
        exc: Exception,
        node_id: str,
        node_type: str,
        config: dict[str, Any],
        children: dict[str, list[str]],
        edge_branches: dict[tuple[str, str], str | None],
        node_status: dict[str, str],
        node_outputs: dict[str, Any],
        params: WorkflowExecutorParams,
    ) -> None:
        """Record the error state; caller decides whether to re-raise."""
        # Unwrap to the real cause (Temporal wraps activity failures); the node
        # is already known here so don't re-prefix it with the step name.
        error_msg = _describe_failure(exc, None, None)
        node_status[node_id] = "error"
        node_outputs[node_id] = {"error": error_msg}
        await _record_node_done(
            params.execution_id, node_id, node_type, {}, error_msg, "error"
        )

    # ── For-each body executor ────────────────────────────────────────────────

    async def _run_for_each_body(
        self,
        config: dict[str, Any],
        item_input: dict[str, Any],
        params: WorkflowExecutorParams,
    ) -> dict[str, Any]:
        """
        Execute the body_nodes / body_edges mini-DAG for a single for_each item.
        Returns the output of the last executed body node.
        """
        body_nodes: list[dict[str, Any]] = config.get("body_nodes", [])
        body_edges: list[dict[str, Any]] = config.get("body_edges", [])

        if not body_nodes:
            return item_input  # No body — pass through

        # Build adjacency for body
        b_children: dict[str, list[str]] = {n["id"]: [] for n in body_nodes}
        b_parents: dict[str, list[str]] = {n["id"]: [] for n in body_nodes}
        b_edge_branches: dict[tuple[str, str], str | None] = {}

        for edge in body_edges:
            frm, to = edge["from"], edge["to"]
            b_children[frm].append(to)
            b_parents[to].append(frm)
            b_edge_branches[(frm, to)] = edge.get("branch") or None

        ordered = _topological_sort(body_nodes, b_children)
        b_outputs: dict[str, Any] = {}
        b_status: dict[str, str] = {}
        last_output: dict[str, Any] = item_input

        for node_id in ordered:
            node = next((n for n in body_nodes if n["id"] == node_id), None)
            if node is None:
                continue
            node_type = node["type"]
            node_cfg = node.get("config", {})

            parent_ids = b_parents.get(node_id, [])
            if parent_ids and not _should_execute_node(
                node_id, parent_ids, b_edge_branches, b_status
            ):
                b_status[node_id] = "skipped"
                b_outputs[node_id] = {}
                continue

            node_input = _build_node_input(
                node_id, parent_ids, b_edge_branches, b_status, b_outputs, item_input
            )

            output = await self._execute_node(
                node_id, node_type, node_cfg, node_input, params
            )
            b_status[node_id] = "success"
            b_outputs[node_id] = output
            last_output = output

        return last_output

    # ── Activity dispatcher ───────────────────────────────────────────────────

    async def _execute_node(
        self,
        node_id: str,
        node_type: str,
        config: dict[str, Any],
        input_data: dict[str, Any],
        params: WorkflowExecutorParams,
    ) -> dict[str, Any]:
        timeout = timedelta(minutes=config.get("timeout_minutes", 5))

        await workflow.execute_activity(
            emit_log_event,
            LogEventParams(
                execution_id=params.execution_id,
                node_id=node_id,
                event="started",
                data={},
            ),
            start_to_close_timeout=timedelta(seconds=5),
            retry_policy=NO_RETRY,
        )

        match node_type:
            case "http_request":
                result = await workflow.execute_activity(
                    http_request,
                    HttpParams(
                        url=_interpolate(config["url"], input_data),
                        method=config.get("method", "GET"),
                        headers=config.get("headers", {}),
                        body=config.get("body"),
                        credential_id=config.get("credential_id"),
                        org_id=params.org_id,
                    ),
                    start_to_close_timeout=timeout,
                    retry_policy=DEFAULT_RETRY,
                )

            case "pack_action":
                # Pack-contributed action node: the `node_key` field
                # identifies which manifest spec to dispatch. The
                # activity reads the pack_node_types row, builds the
                # `/api/{pack}/v1{endpoint_path}` URL, and POSTs the
                # remaining config as the body. Token interpolation
                # on individual config values happens here so the
                # pack endpoint receives concrete values, not
                # ``{{trigger.id}}`` strings.
                resolved_config: dict[str, Any] = {}
                for k, v in (config or {}).items():
                    if k == "node_key":
                        resolved_config[k] = v
                    elif isinstance(v, str):
                        resolved_config[k] = _interpolate(v, input_data)
                    else:
                        resolved_config[k] = v
                result = await workflow.execute_activity(
                    dispatch_pack_action,
                    PackActionParams(
                        node_key=str(resolved_config.get("node_key") or ""),
                        config=resolved_config,
                        org_id=params.org_id,
                    ),
                    start_to_close_timeout=timeout,
                    retry_policy=DEFAULT_RETRY,
                )

            case "web_scraper":
                result = await workflow.execute_activity(
                    "scrape_page",
                    {
                        "url": _interpolate(config["url"], input_data),
                        "session_id": config.get("session_id"),
                        "selectors": config.get("selectors", []),
                        "actions": config.get("actions", []),
                        "org_id": params.org_id,
                    },
                    start_to_close_timeout=timedelta(minutes=10),
                    retry_policy=NO_RETRY,
                )

            case "transform":
                result = await workflow.execute_activity(
                    transform_data,
                    TransformParams(
                        input_data=input_data,
                        expression=config["expression"],
                        engine=config.get("engine", "jmespath"),
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=NO_RETRY,
                )

            case "run_code":
                result = await workflow.execute_activity(
                    run_code,
                    CodeParams(
                        code=config["code"],
                        input_data=input_data,
                        language=config.get("language", "python"),
                    ),
                    start_to_close_timeout=timedelta(minutes=2),
                    retry_policy=NO_RETRY,
                )

            case "db_query":
                # S5 — SQL is passed verbatim ($1/$2 placeholders only); dynamic
                # values are interpolated into the *params* list and bound by the
                # driver, never substituted into the SQL string. Interpolating
                # config["sql"] here was second-order SQLi.
                result = await workflow.execute_activity(
                    run_db_query,
                    DbQueryParams(
                        sql=config["sql"],
                        params=[
                            _interpolate(p, input_data) if isinstance(p, str) else p
                            for p in config.get("params", [])
                        ],
                        credential_id=config.get("credential_id"),
                        org_id=params.org_id,
                    ),
                    start_to_close_timeout=timeout,
                    retry_policy=DEFAULT_RETRY,
                )

            case "send_email":
                result = await workflow.execute_activity(
                    send_email,
                    EmailParams(
                        to=_interpolate(config["to"], input_data),
                        subject=_interpolate(config["subject"], input_data),
                        body=_interpolate(config.get("body", ""), input_data),
                        credential_id=config.get("credential_id"),
                        org_id=params.org_id,
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=DEFAULT_RETRY,
                )

            case "delay":
                await workflow.sleep(timedelta(seconds=config.get("seconds", 60)))
                result = input_data

            case "stripe":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="stripe/call",
                        payload={
                            "credential_id": config["credential_id"],
                            "endpoint": _interpolate(
                                config.get("endpoint", "/v1/charges"), input_data
                            ),
                            "method": config.get("method", "GET"),
                            "data": {
                                k: _interpolate(str(v), input_data)
                                for k, v in config.get("data", {}).items()
                            },
                        },
                    ),
                    start_to_close_timeout=timeout,
                    retry_policy=DEFAULT_RETRY,
                )

            case "mailchimp":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="mailchimp/member",
                        payload={
                            "credential_id": config["credential_id"],
                            "operation": config.get("operation", "subscribe"),
                            "list_id": config["list_id"],
                            "email": _interpolate(
                                config.get("email", "{{email}}"), input_data
                            ),
                            "merge_fields": config.get("merge_fields", {}),
                            "tags": config.get("tags", []),
                        },
                    ),
                    start_to_close_timeout=timeout,
                    retry_policy=DEFAULT_RETRY,
                )

            case "claude_llm":
                result = await workflow.execute_activity(
                    run_llm,
                    LLMParams(
                        credential_id=config["credential_id"],
                        org_id=params.org_id,
                        prompt=_interpolate(config.get("prompt", ""), input_data),
                        system_prompt=config.get("system_prompt", ""),
                        model=config.get("model", "claude-sonnet-4-6"),
                        provider_type=config.get("provider", "anthropic"),
                        max_tokens=int(config.get("max_tokens", 1024)),
                    ),
                    start_to_close_timeout=timedelta(minutes=5),
                    retry_policy=DEFAULT_RETRY,
                )

            case "action_node":
                # Phase F1.5 — invoke a registered ActionTool by name via
                # integration-hub's /ai-tools/run. ``skill_name`` is the
                # smart_llm.registry key; ``args`` is the typed dict
                # validated against the tool's args_model on the server.
                # All string-shaped args are interpolated against the
                # node's input_data, matching the convention used by
                # claude_llm/email/etc.
                _raw_args = config.get("args", {}) or {}
                _interp_args = {
                    k: (_interpolate(v, input_data) if isinstance(v, str) else v)
                    for k, v in _raw_args.items()
                }
                result = await workflow.execute_activity(
                    run_action_node,
                    ActionParams(
                        skill_name=config["skill_name"],
                        args=_interp_args,
                        org_id=params.org_id,
                        timeout_seconds=int(config.get("timeout_seconds", 60)),
                    ),
                    start_to_close_timeout=timedelta(minutes=5),
                    retry_policy=DEFAULT_RETRY,
                )

            case "agent_node":
                # Phase B — invoke a configured AIAgentConfig by UUID via
                # integration-hub's /ai-invoke/run. ``agent_id`` is stored
                # in the node config by the Flutter agent_node_config.dart
                # form. The ``input`` (or ``prompt``) field is interpolated
                # against the node's input_data so prior-node outputs can
                # flow into the agent's user message.
                _agent_input = _interpolate(
                    config.get("input", config.get("prompt", "")), input_data
                )
                _agent_context = config.get("context")
                if isinstance(_agent_context, str):
                    _agent_context = _interpolate(_agent_context, input_data)
                if config.get("agentic"):
                    # Reactive multi-step autonomous run — child workflow so the
                    # tool-policy gate's high-risk approvals can durably pause.
                    import uuid as _uuid_run

                    _run_id = str(_uuid_run.uuid4())
                    _child = await workflow.execute_child_workflow(
                        AgentRunWorkflow.run,
                        AgentRunParams(
                            agent_id=config["agent_id"],
                            org_id=params.org_id,
                            prompt=_agent_input,
                            run_id=_run_id,
                            max_steps=int(config.get("max_steps", 25)),
                            approval_timeout_hours=int(
                                config.get("approval_timeout_hours", 72)
                            ),
                        ),
                        id=f"agentrun-{params.execution_id}-{node_id}",
                    )
                    result = {
                        "data": {"content": _child.content},
                        "status": _child.status,
                        "steps": _child.steps,
                        "run_id": _run_id,
                    }
                else:
                    # Identify the agent by portable qualified name when the
                    # node supplies one (``agent_name``, e.g. a vertical-app
                    # seed workflow referencing ``restoration:project_summary``);
                    # otherwise by per-company ``agent_id`` UUID.
                    result = await workflow.execute_activity(
                        run_agent_node,
                        AgentParams(
                            agent_id=config.get("agent_id"),
                            agent_name=config.get("agent_name"),
                            prompt=_agent_input,
                            org_id=params.org_id,
                            context=_agent_context,
                            timeout_seconds=int(config.get("timeout_seconds", 120)),
                        ),
                        start_to_close_timeout=timedelta(minutes=10),
                        retry_policy=DEFAULT_RETRY,
                    )

            case "agent_graph_node":
                # Phase E2 — multi-agent orchestration. ``spec`` is the
                # AgentGraphSpec JSON authored by the Flutter
                # node_config_panel.dart form; ``input`` is the entry
                # agent's user message. The smart_llm.orchestrator
                # module validates cycles + enforces MAX_DEPTH=3 server-
                # side before any LLM call fires, so we don't need any
                # workflow-side guardrails beyond the activity timeout.
                _graph_input = _interpolate(
                    config.get("input", config.get("prompt", "")), input_data
                )
                _graph_context = config.get("context")
                if isinstance(_graph_context, str):
                    _graph_context = _interpolate(_graph_context, input_data)
                # The Flutter form stores `spec` as a JSON STRING (it's
                # a multiline text input). Decode to dict so the
                # orchestrator sees the typed shape. Already-dict values
                # (e.g. from programmatic workflow construction) pass
                # through untouched.
                _spec_raw = config.get("spec", "{}")
                if isinstance(_spec_raw, str):
                    import json as _json

                    try:
                        _spec = _json.loads(_spec_raw or "{}")
                    except _json.JSONDecodeError as e:
                        raise ValueError(
                            f"agent_graph_node spec is not valid JSON: {e}"
                        )
                else:
                    _spec = _spec_raw or {}
                result = await workflow.execute_activity(
                    run_agent_graph_node,
                    AgentGraphParams(
                        spec=_spec,
                        input_text=_graph_input,
                        org_id=params.org_id,
                        context=_graph_context,
                        timeout_seconds=int(config.get("timeout_seconds", 300)),
                    ),
                    start_to_close_timeout=timedelta(minutes=15),
                    retry_policy=DEFAULT_RETRY,
                )

            case "s3":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="s3/operation",
                        payload={
                            "credential_id": config["credential_id"],
                            "operation": config.get("operation", "list"),
                            "bucket": config["bucket"],
                            "key": _interpolate(config.get("key", ""), input_data),
                            "body": _interpolate(config.get("body", ""), input_data),
                            "content_type": config.get("content_type", ""),
                            "region": config.get("region", "us-east-1"),
                        },
                        timeout_seconds=600,
                    ),
                    start_to_close_timeout=timedelta(minutes=10),
                    retry_policy=DEFAULT_RETRY,
                )

            case "google_drive":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="google-drive/operation",
                        payload={
                            "credential_id": config["credential_id"],
                            "operation": config.get("operation", "list"),
                            "file_id": config.get("file_id", ""),
                            "file_name": _interpolate(
                                config.get("file_name", ""), input_data
                            ),
                            "folder_id": config.get("folder_id", ""),
                            "mime_type": config.get("mime_type", ""),
                            "body": _interpolate(config.get("body", ""), input_data),
                            "query": config.get("query", ""),
                        },
                        timeout_seconds=600,
                    ),
                    start_to_close_timeout=timedelta(minutes=10),
                    retry_policy=DEFAULT_RETRY,
                )

            case "gmail_send":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="gmail/send",
                        payload={
                            "credential_id": config["credential_id"],
                            "to": _interpolate(config["to"], input_data),
                            "subject": _interpolate(
                                config.get("subject", ""), input_data
                            ),
                            "body": _interpolate(config.get("body", ""), input_data),
                            "body_html": _interpolate(
                                config.get("body_html", ""), input_data
                            ),
                            "cc": config.get("cc", ""),
                            "bcc": config.get("bcc", ""),
                        },
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=DEFAULT_RETRY,
                )

            case "gmail_read":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="gmail/read",
                        payload={
                            "credential_id": config["credential_id"],
                            "query": _interpolate(
                                config.get("query", "is:unread"), input_data
                            ),
                            "max_results": int(config.get("max_results", 10)),
                            "mark_as_read": config.get("mark_as_read", "false").lower()
                            == "true",
                        },
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=DEFAULT_RETRY,
                )

            case "outlook_send":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="outlook/send",
                        payload={
                            "credential_id": config["credential_id"],
                            "to": _interpolate(config["to"], input_data),
                            "subject": _interpolate(
                                config.get("subject", ""), input_data
                            ),
                            "body": _interpolate(config.get("body", ""), input_data),
                            "body_html": _interpolate(
                                config.get("body_html", ""), input_data
                            ),
                            "cc": config.get("cc", ""),
                            "save_to_sent": config.get("save_to_sent", "true").lower()
                            == "true",
                        },
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=DEFAULT_RETRY,
                )

            case "outlook_read":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="outlook/read",
                        payload={
                            "credential_id": config["credential_id"],
                            "folder": config.get("folder", "Inbox"),
                            "filter_query": config.get(
                                "filter_query", "isRead eq false"
                            ),
                            "max_results": int(config.get("max_results", 10)),
                            "mark_as_read": config.get("mark_as_read", "false").lower()
                            == "true",
                        },
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=DEFAULT_RETRY,
                )

            case "excel_read":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="excel/read",
                        payload={
                            "file_base64": _interpolate(
                                config.get("file_base64", "{{file_base64}}"), input_data
                            ),
                            "sheet_name": config.get("sheet_name", ""),
                            "has_header": config.get("has_header", "true").lower()
                            == "true",
                            "max_rows": int(config.get("max_rows", 0)),
                        },
                        timeout_seconds=120,
                    ),
                    start_to_close_timeout=timedelta(minutes=2),
                    retry_policy=NO_RETRY,
                )

            case "excel_write":
                result = await workflow.execute_activity(
                    call_integration_hub,
                    IntegrationHubParams(
                        endpoint="excel/write",
                        payload={
                            "rows": input_data.get("rows", []),
                            "sheet_name": config.get("sheet_name", "Sheet1"),
                            "include_header": config.get(
                                "include_header", "true"
                            ).lower()
                            == "true",
                        },
                        timeout_seconds=120,
                    ),
                    start_to_close_timeout=timedelta(minutes=2),
                    retry_policy=NO_RETRY,
                )

            case "evaluate_rules":
                result = await workflow.execute_activity(
                    evaluate_rules,
                    EvaluateRulesParams(
                        event_type=config.get("event_type", "manual"),
                        event_data=input_data,
                        org_id=params.org_id,
                        dry_run=config.get("dry_run", "false").lower() == "true",
                    ),
                    start_to_close_timeout=timedelta(seconds=30),
                    retry_policy=NO_RETRY,
                )

            case _:
                raise ValueError(f"Unknown node type: {node_type}")

        return cast(dict[str, Any], result)


# ── Branch routing helpers ────────────────────────────────────────────────────


def _is_edge_live(
    edge_branch: str | None,
    parent_status: str,
) -> bool:
    """
    Return True if a parent→child edge should be traversed given the parent's
    execution status and the edge's branch label.

    Branch labels:
      None         → unconditional (live for any non-skipped, non-error success)
      "true"       → live when parent is "true_branch"
      "false"      → live when parent is "false_branch"
      "success"    → live when parent is "success"
      "error"      → live when parent is "error"
      "switch_*"   → live when parent_status == "switch_{label}"
      any string   → treated as switch case label
    """
    if parent_status == "skipped":
        return False
    if edge_branch is None:
        # Unconditional: live for all success variants (not error/skipped)
        return parent_status in (
            "success",
            "true_branch",
            "false_branch",
        ) or parent_status.startswith("switch_")
    match edge_branch:
        case "true":
            return parent_status == "true_branch"
        case "false":
            return parent_status == "false_branch"
        case "success":
            return parent_status == "success"
        case "error":
            return parent_status == "error"
        case _:
            # Switch case label
            return parent_status == f"switch_{edge_branch}"


def _should_execute_node(
    node_id: str,
    parent_ids: list[str],
    edge_branches: dict[tuple[str, str], str | None],
    node_status: dict[str, str],
) -> bool:
    """
    A node should execute if at least one of its incoming edges is live.
    If all edges are dead (wrong branch, skipped parents), the node is skipped.
    """
    for pid in parent_ids:
        branch = edge_branches.get((pid, node_id))
        pstatus = node_status.get(pid, "success")
        if _is_edge_live(branch, pstatus):
            return True
    return False


def _build_node_input(
    node_id: str,
    parent_ids: list[str],
    edge_branches: dict[tuple[str, str], str | None],
    node_status: dict[str, str],
    node_outputs: dict[str, Any],
    fallback: dict[str, Any],
) -> dict[str, Any]:
    """
    Merge outputs from all live parent edges into a single input dict.
    Falls back to the workflow input_data if the node has no parents.
    """
    if not parent_ids:
        return fallback
    merged: dict[str, Any] = {}
    any_live = False
    for pid in parent_ids:
        branch = edge_branches.get((pid, node_id))
        pstatus = node_status.get(pid, "success")
        if _is_edge_live(branch, pstatus):
            merged.update(node_outputs.get(pid, {}))
            any_live = True
    return merged if any_live else fallback


def _has_error_edges(
    node_id: str,
    children: dict[str, list[str]],
    edge_branches: dict[tuple[str, str], str | None],
) -> bool:
    """Return True if this node has at least one outgoing error-branch edge."""
    for cid in children.get(node_id, []):
        if edge_branches.get((node_id, cid)) == "error":
            return True
    return False


def _merge_parent_outputs(
    node_id: str,
    parent_ids: list[str],
    edge_branches: dict[tuple[str, str], str | None],
    node_status: dict[str, str],
    node_outputs: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    """
    Collect live parent outputs and combine them according to merge mode.

    Modes:
      merge  (default) — dict.update all live parent outputs (last writer wins)
      append           — {"items": [output1, output2, ...]}
      first            — first live parent's output only
      last             — last live parent's output only
    """
    mode = config.get("mode", "merge")
    live_outputs: list[dict[str, Any]] = []
    for pid in parent_ids:
        branch = edge_branches.get((pid, node_id))
        pstatus = node_status.get(pid, "success")
        if _is_edge_live(branch, pstatus):
            live_outputs.append(node_outputs.get(pid, {}))

    if not live_outputs:
        return {}

    match mode:
        case "append":
            return {"items": live_outputs}
        case "first":
            return live_outputs[0]
        case "last":
            return live_outputs[-1]
        case _:  # "merge"
            merged: dict[str, Any] = {}
            for out in live_outputs:
                merged.update(out)
            return merged


# ── General helpers ───────────────────────────────────────────────────────────


def _topological_sort(
    nodes: list[dict[str, Any]], children: dict[str, list[str]]
) -> list[str]:
    """Kahn's algorithm for topological sort of the DAG."""
    in_degree = {n["id"]: 0 for n in nodes}
    for node_id, kids in children.items():
        for kid in kids:
            in_degree[kid] += 1

    queue = deque([n["id"] for n in nodes if in_degree[n["id"]] == 0])
    order: list[str] = []
    while queue:
        nid = queue.popleft()
        order.append(nid)
        for kid in children.get(nid, []):
            in_degree[kid] -= 1
            if in_degree[kid] == 0:
                queue.append(kid)
    return order


def _interpolate(template: str, data: dict[str, Any]) -> str:
    """Simple {{variable.path}} interpolation from input data."""

    def replacer(match: re.Match[str]) -> str:
        key = match.group(1).strip()
        return str(_get_nested(data, key) or "")

    return re.sub(r"\{\{(.+?)\}\}", replacer, str(template))


def _get_nested(data: Any, path: str) -> Any:
    """Resolve a dot-separated field path in a nested dict."""
    val = data
    for part in path.split("."):
        if isinstance(val, dict):
            val = val.get(part)
        else:
            return None
    return val


async def _record_node_start(
    execution_id: str, node_id: str, node_type: str, input_data: dict[str, Any]
) -> None:
    await workflow.execute_activity(
        update_node_execution,
        NodeExecutionUpdate(
            execution_id=execution_id,
            node_id=node_id,
            node_type=node_type,
            status="running",
            input_data=input_data,
            output_data={},
        ),
        start_to_close_timeout=timedelta(seconds=10),
    )


async def _record_node_done(
    execution_id: str,
    node_id: str,
    node_type: str,
    output: dict[str, Any],
    error: str | None,
    status: str = "completed",
) -> None:
    db_status = (
        "skipped" if status == "skipped" else ("failed" if error else "completed")
    )
    await workflow.execute_activity(
        update_node_execution,
        NodeExecutionUpdate(
            execution_id=execution_id,
            node_id=node_id,
            node_type=node_type,
            status=db_status,
            input_data={},
            output_data=output or {},
            error_message=error,
        ),
        start_to_close_timeout=timedelta(seconds=10),
    )
