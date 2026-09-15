"""Vendored platform utilities.

These modules were originally provided by the SentinelBuild internal SDK
(``sentinelbuild_sdk``). They are small, self-contained helpers — settings,
error types, an SSRF egress guard, a base HTTP client, the smart-llm invoke
client, a per-IP rate limiter, security headers, and an optional authorization
hook — vendored here verbatim (with imports rehomed under ``shared._platform``)
so the workflow engine is a dependency-clean standalone service. Keep them in
sync with upstream if you pull fixes from the platform SDK.
"""

from shared._platform.config import SentinelBuildSettings
from shared._platform.smart_llm_invoke import SmartLlmInvokeClient

__all__ = ["SentinelBuildSettings", "SmartLlmInvokeClient"]
