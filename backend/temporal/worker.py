"""Temporal worker — registers all workflows and activities."""

import asyncio
import signal

import structlog
from smart_llm.logging_config import configure_logging

from shared.config import get_settings

configure_logging(service_name="mit-stack-worker")

from smart_llm.service_runtime import graceful_shutdown_timeout as _grace_timeout
from temporalio.worker import Worker

from temporal.activities.action_activity import run_action_node
from temporal.activities.agent_activity import run_agent_node
from temporal.activities.agent_graph_activity import run_agent_graph_node
from temporal.activities.agent_run_status_activity import report_agent_run_status
from temporal.activities.agent_turn_activity import (
    run_agent_tool_dispatch,
    run_agent_turn,
)
from temporal.activities.approval_activity import (
    register_approval_token,
    send_approval_email,
)
from temporal.activities.call_workflow_activity import call_sub_workflow
from temporal.activities.code_activity import run_code
from temporal.activities.condition_activity import evaluate_condition
from temporal.activities.db_activity import run_db_query
from temporal.activities.domain_condition_activity import evaluate_domain_condition
from temporal.activities.email_activity import send_email
from temporal.activities.http_activity import http_request
from temporal.activities.imap_activity import fetch_new_emails
from temporal.activities.integration_hub_activity import call_integration_hub
from temporal.activities.llm_activity import run_llm
from temporal.activities.notify_activity import notify_workflow_event
from temporal.activities.pack_action_activity import dispatch_pack_action
from temporal.activities.rule_engine_activity import evaluate_rules
from temporal.activities.scheduled_call_activity import perform_scheduled_call
from temporal.activities.scraper_activity import (
    login_and_capture_session,
    refresh_scraper_session,
    scrape_page,
)
from temporal.activities.state_activity import (
    create_execution_record,
    emit_log_event,
    load_workflow_definition,
    update_execution_status,
    update_node_execution,
)
from temporal.activities.transform_activity import transform_data
from temporal.workflows.agent_run_workflow import AgentRunWorkflow
from temporal.workflows.imap_polling_workflow import ImapPollingWorkflow
from temporal.workflows.refresh_scraper_session_workflow import (
    RefreshScraperSessionWorkflow,
)
from temporal.workflows.scheduled_call_workflow import ScheduledCallWorkflow
from temporal.workflows.scrape_page_workflow import ScrapePageWorkflow
from temporal.workflows.workflow_executor import WorkflowExecutor

log = structlog.get_logger(__name__)

settings = get_settings()


async def main() -> None:
    log.info(
        "worker_starting",
        temporal_host=settings.temporal_host,
        task_queue=settings.temporal_task_queue,
    )
    from shared.temporal_client import get_temporal_client

    client = await get_temporal_client()

    from shared.temporal_interceptor import LoggingInterceptor

    worker = Worker(
        client,
        task_queue=settings.temporal_task_queue,
        graceful_shutdown_timeout=_grace_timeout(),  # drain in-flight on SIGTERM
        max_concurrent_activities=settings.temporal_worker_concurrency,
        max_concurrent_workflow_tasks=settings.temporal_max_concurrent_workflow_tasks,
        workflows=[
            WorkflowExecutor,
            ImapPollingWorkflow,
            AgentRunWorkflow,
            RefreshScraperSessionWorkflow,
            ScrapePageWorkflow,
            ScheduledCallWorkflow,
        ],
        interceptors=[LoggingInterceptor()],
        activities=[
            # State management
            update_execution_status,
            update_node_execution,
            emit_log_event,
            load_workflow_definition,
            create_execution_record,
            # Node activities
            http_request,
            scrape_page,
            login_and_capture_session,
            refresh_scraper_session,
            transform_data,
            evaluate_condition,
            evaluate_domain_condition,
            run_code,
            send_email,
            run_db_query,
            # Approval nodes (wait_approval: register the approval token +
            # send the approval-request email). Without these registered the
            # activity task fails with "activity function is not registered".
            register_approval_token,
            send_approval_email,
            # Sub-workflow node (call_workflow: invoke another workflow as a step).
            call_sub_workflow,
            # IMAP polling
            fetch_new_emails,
            # Integration Hub (delegates 3rd-party calls to Integration Hub service)
            call_integration_hub,
            # Phase F1.5 — registered ActionTool dispatch via Integration Hub
            run_action_node,
            # Phase B — agent_node dispatch (configured AIAgentConfig invocation)
            run_agent_node,
            # Phase E2 — agent_graph_node dispatch (multi-agent orchestration)
            run_agent_graph_node,
            # Autonomous-agent durable run (AgentRunWorkflow turn + dispatch + status)
            run_agent_turn,
            run_agent_tool_dispatch,
            report_agent_run_status,
            # LLM (direct smart-llm calls for claude_llm workflow nodes)
            run_llm,
            evaluate_rules,
            # Notifications (workflow lifecycle events → Integration Hub)
            notify_workflow_event,
            # Pack-contributed action dispatcher (sb_pack manifest →
            # pack_node_types row → pack-owned HTTP endpoint).
            dispatch_pack_action,
            # Generic scheduled outbound call (cron → HTTP). First user: SLA sweep.
            perform_scheduled_call,
        ],
    )
    log.info("worker_started", task_queue=settings.temporal_task_queue)

    # Graceful drain: on SIGTERM/SIGINT stop polling and let in-flight
    # activities finish (Temporal redelivers anything not completed) instead of
    # a hard kill — required for zero-drop rolling deploys / replica scale-down.
    shutdown = asyncio.Event()

    def _drain() -> None:
        log.info("worker_shutdown_signal")
        shutdown.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _drain)
        except NotImplementedError:  # Windows
            pass

    async with worker:
        await shutdown.wait()
    log.info("worker_shutdown_complete")


if __name__ == "__main__":
    asyncio.run(main())
