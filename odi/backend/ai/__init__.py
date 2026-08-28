"""OdiAI backend AI service layer.

Public surface (re-exported from submodules):

    generate_reply(message, history=None) -> str
    stream_reply(message, history=None) -> AsyncIterator[str]
    AIServiceError, RetryableError, PermanentError
    SYSTEM_PROMPT

The implementation is split into:

    ai.errors       - typed exceptions used at the provider boundary
    ai.providers    - one concrete provider per backend (Gemini / OpenAI / Anthropic)
    ai.chain        - the chain executor that walks configured providers with
                      automatic fallback on transient (retryable) errors

The chain is configured via the ``ODIAI_MODEL_CHAIN`` env var, e.g.::

    ODIAI_MODEL_CHAIN=gemini:gemini-3.5-flash-lite,openai:gpt-4o-mini,anthropic:claude-haiku-4-5-20251001

Providers whose API key is not configured are skipped silently with an INFO log.
"""

from __future__ import annotations

from ai.chain import generate_reply, stream_reply
from ai.errors import AIServiceError, PermanentError, RetryableError

# IMPORTANT: kept here (not in chain.py) so callers can reference it without
# importing the chain executor. The same string is sent on every request
# regardless of which provider answers.
SYSTEM_PROMPT = (
    "You are OdiAI, a friendly and concise personal AI assistant. "
    "Answer the user's questions clearly and helpfully. If you don't "
    "know the answer, say so honestly rather than inventing facts."
)

# IMPORTANT: kept for backward compatibility with code (or tests) that still
# imports ``ai.MODEL_NAME``. The chain's default chain is the source of truth
# for which model is used at runtime; this constant is the legacy single-model
# hint used by older callers and integration tests.
MODEL_NAME = "gemini-3.5-flash-lite"

__all__ = [
    "AIServiceError",
    "MODEL_NAME",
    "PermanentError",
    "RetryableError",
    "SYSTEM_PROMPT",
    "generate_reply",
    "stream_reply",
]
