"""Temporal SDK interceptors for structured logging of workflow/activity lifecycle."""

from datetime import UTC, datetime
from typing import Any

import structlog
from temporalio import workflow
from temporalio.worker import (
    ActivityInboundInterceptor,
    ExecuteActivityInput,
    ExecuteWorkflowInput,
    Interceptor,
    WorkflowInboundInterceptor,
    WorkflowInterceptorClassInput,
)

log = structlog.get_logger(__name__)


def _safe_workflow_type(input: ExecuteWorkflowInput) -> str:
    """Best-effort name of the executing workflow.

    `input.run_fn` may be a bound method (has `__self__`), an unbound
    function, or a partial — depending on how the workflow was defined
    and the SDK version. Fall back to `workflow.info().workflow_type`,
    which is always available inside the workflow sandbox.
    """
    fn = getattr(input, "run_fn", None)
    self_obj = getattr(fn, "__self__", None)
    if self_obj is not None:
        return type(self_obj).__name__
    try:
        return workflow.info().workflow_type
    except Exception:
        qualname = getattr(fn, "__qualname__", None)
        if isinstance(qualname, str):
            return qualname
        name = getattr(fn, "__name__", None)
        return name if isinstance(name, str) else "unknown"


class _LoggingWorkflowInterceptor(WorkflowInboundInterceptor):
    async def execute_workflow(self, input: ExecuteWorkflowInput) -> Any:
        wf_type = _safe_workflow_type(input)
        log.info("workflow_start", workflow_type=wf_type)
        try:
            result = await self.next.execute_workflow(input)
            log.info("workflow_complete", workflow_type=wf_type)
            return result
        except Exception:
            log.error("workflow_failed", workflow_type=wf_type, exc_info=True)
            raise


class _LoggingActivityInterceptor(ActivityInboundInterceptor):
    async def execute_activity(self, input: ExecuteActivityInput) -> Any:
        activity_name = input.fn.__name__
        start = datetime.now(UTC)
        log.info("activity_start", activity=activity_name)
        try:
            result = await self.next.execute_activity(input)
            elapsed_ms = round((datetime.now(UTC) - start).total_seconds() * 1000, 1)
            log.info(
                "activity_complete", activity=activity_name, duration_ms=elapsed_ms
            )
            return result
        except Exception:
            elapsed_ms = round((datetime.now(UTC) - start).total_seconds() * 1000, 1)
            log.error(
                "activity_failed",
                activity=activity_name,
                duration_ms=elapsed_ms,
                exc_info=True,
            )
            raise


class LoggingInterceptor(Interceptor):
    def workflow_interceptor_class(
        self, input: WorkflowInterceptorClassInput
    ) -> type[WorkflowInboundInterceptor] | None:
        return _LoggingWorkflowInterceptor

    def intercept_activity(
        self, next: ActivityInboundInterceptor
    ) -> ActivityInboundInterceptor:
        return _LoggingActivityInterceptor(next)
