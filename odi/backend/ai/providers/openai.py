"""OpenAI provider.

Translates between:

    - Wire format (Flutter):  ``{"role": "user"|"assistant", "text": ...}``
    - OpenAI Chat format:     ``{"role": ..., "content": "..."}``

The system prompt is supplied as a leading ``{"role": "system", "content": ...}``
message in the messages list (OpenAI's canonical way; there is no separate
top-level ``system`` field).

Error classification (per the plan):

    RetryableError:  ``RateLimitError`` (429), ``APITimeoutError``,
                     ``APIConnectionError``, ``APIStatusError`` with 5xx.
    PermanentError:  ``BadRequestError`` (400), ``AuthenticationError`` (401),
                     ``PermissionDeniedError`` (403), ``NotFoundError`` (404),
                     empty ``choices[0].message.content``.
"""

from __future__ import annotations

import logging
import os
from typing import Any, AsyncIterator

from ai.errors import PermanentError, RetryableError
from ai.providers import register
from ai.providers.base import BaseProvider

logger = logging.getLogger(__name__)

# Lazy imports so a missing SDK doesn't break the chain at import time.
_openai = None
_openai_exception = None


def _import_sdk() -> None:
    global _openai, _openai_exception
    if _openai is not None:
        return
    import openai
    from openai import AsyncOpenAI

    _openai = openai
    _openai_exception = openai


# OpenAI exception classes we care about. They're looked up dynamically
# inside ``_classify_api_error`` so we don't need to pin specific symbols
# at import time.
def _exceptions():
    """Return (APIStatusError, RateLimitError, APITimeoutError, APIConnectionError, BadRequestError, AuthenticationError, PermissionDeniedError, NotFoundError)."""
    _import_sdk()
    assert _openai is not None
    return (
        _openai.APIStatusError,
        _openai.RateLimitError,
        _openai.APITimeoutError,
        _openai.APIConnectionError,
        _openai.BadRequestError,
        _openai.AuthenticationError,
        _openai.PermissionDeniedError,
        _openai.NotFoundError,
    )


_RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class OpenAIProvider(BaseProvider):
    name = "openai"

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self._client: Any | None = None

    def is_configured(self) -> bool:
        return bool(os.environ.get("OPENAI_API_KEY", "").strip())

    def _get_client(self) -> Any:
        if self._client is not None:
            return self._client
        _import_sdk()
        assert _openai is not None
        key = os.environ.get("OPENAI_API_KEY", "").strip()
        if not key:
            raise PermanentError("OPENAI_API_KEY is not configured on the server.")
        self._client = _openai.AsyncOpenAI(api_key=key)
        return self._client

    def build_request(
        self,
        message: str,
        history: list[dict] | None,
    ) -> tuple[Any, str]:
        messages = _build_messages(message, history)
        return messages, _SYSTEM_PROMPT_TEXT

    async def generate(self, message: str, history: list[dict] | None) -> str:
        client = self._get_client()
        messages, system_prompt = self.build_request(message, history)
        full_messages = [{"role": "system", "content": system_prompt}] + messages
        try:
            response = await client.chat.completions.create(
                model=self.model,
                messages=full_messages,
                temperature=0.7,
            )
        except Exception as exc:  # noqa: BLE001 - classify below
            raise _classify(exc) from exc

        try:
            content = response.choices[0].message.content
        except (AttributeError, IndexError, TypeError) as exc:
            raise PermanentError(f"Unexpected OpenAI response shape: {exc}") from exc

        text = (content or "").strip() if isinstance(content, str) else ""
        if not text:
            raise PermanentError("The AI returned an empty response. Please try again.")
        return text

    async def stream(
        self,
        message: str,
        history: list[dict] | None,
    ) -> AsyncIterator[str]:
        client = self._get_client()
        messages, system_prompt = self.build_request(message, history)
        full_messages = [{"role": "system", "content": system_prompt}] + messages
        try:
            stream = await client.chat.completions.create(
                model=self.model,
                messages=full_messages,
                temperature=0.7,
                stream=True,
            )
        except Exception as exc:  # noqa: BLE001
            raise _classify(exc) from exc

        # ``stream`` is an async iterator of ChatCompletionChunk. Each
        # chunk has ``choices[0].delta`` whose ``content`` may be ``None``
        # on first/last/role-only chunks — skip those.
        async for chunk in stream:
            try:
                delta = chunk.choices[0].delta
            except (AttributeError, IndexError, TypeError):
                continue
            content = getattr(delta, "content", None)
            if content:
                text = content.strip()
                if text:
                    yield text


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _classify(exc: Exception) -> Exception:
    """Map an OpenAI SDK exception to RetryableError / PermanentError."""
    (
        APIStatusError,
        RateLimitError,
        APITimeoutError,
        APIConnectionError,
        BadRequestError,
        AuthenticationError,
        PermissionDeniedError,
        NotFoundError,
    ) = _exceptions()

    if isinstance(exc, RateLimitError):
        return RetryableError(f"OpenAI rate limit exceeded: {exc}")
    if isinstance(exc, (APITimeoutError, APIConnectionError)):
        return RetryableError(f"OpenAI connection error: {exc}")
    if isinstance(exc, APIStatusError):
        status = getattr(exc, "status_code", None)
        if isinstance(status, int) and status in _RETRYABLE_STATUS:
            return RetryableError(f"OpenAI status {status}: {exc}")
        # Includes 400/401/403/404 or unknown status.
        return PermanentError(f"OpenAI status {status}: {exc}")
    if isinstance(exc, (BadRequestError, AuthenticationError, PermissionDeniedError, NotFoundError)):
        return PermanentError(f"OpenAI request error: {exc}")
    # Anything else is permanent — we don't know what to retry on.
    return PermanentError(f"OpenAI error: {exc}")


def _build_messages(message: str, history: list[dict] | None) -> list[dict]:
    """Translate wire-format history into OpenAI's chat messages format.

    OpenAI accepts consecutive user turns, so we don't have to do the
    alternation-merge gymnastics that Anthropic requires.
    """
    out: list[dict] = []
    if history:
        for turn in history:
            if not isinstance(turn, dict):
                continue
            role = turn.get("role")
            text = turn.get("text")
            if role not in ("user", "assistant"):
                continue
            if not isinstance(text, str) or not text:
                continue
            out.append({"role": role, "content": text})
    out.append({"role": "user", "content": message})
    return out


# IMPORTANT: kept in sync with ``ai.SYSTEM_PROMPT``. See the comment in
# ``ai/providers/gemini.py`` for why this is duplicated.
_SYSTEM_PROMPT_TEXT = (
    "You are OdiAI, a friendly and concise personal AI assistant. "
    "Answer the user's questions clearly and helpfully. If you don't "
    "know the answer, say so honestly rather than inventing facts."
)


register("openai", OpenAIProvider)
