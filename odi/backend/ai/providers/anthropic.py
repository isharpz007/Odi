"""Anthropic provider.

Translates between:

    - Wire format (Flutter):  ``{"role": "user"|"assistant", "text": ...}``
    - Anthropic Messages API: ``messages=[{role, content}]`` + top-level
      ``system`` + ``max_tokens``.

Key Anthropic specifics:

    - System prompt is a top-level ``system`` parameter (not a message).
    - ``max_tokens`` is required; we default to 1024. Long histories plus
      a long new message can exceed this — out of scope to tune
      dynamically for now.
    - Messages must strictly alternate ``user`` / ``assistant``. If the
      wire-format history ends on a user turn and the new turn is also
      user, we merge their texts to keep alternation valid. This is
      defensive; Flutter's invariant is alternating turns, so it
      shouldn't fire in practice.

Error classification:

    RetryableError:  ``APIStatusError`` with 429/5xx, ``APITimeoutError``,
                     ``APIConnectionError``.
    PermanentError:  400/401/403/404 status errors, empty content blocks,
                     refusal text treated as a regular reply (not an
                     exception) — we surface what Anthropic gives us.
"""

from __future__ import annotations

import logging
import os
from typing import Any, AsyncIterator

from ai.errors import PermanentError, RetryableError
from ai.providers import register
from ai.providers.base import BaseProvider

logger = logging.getLogger(__name__)

_anthropic = None


def _import_sdk() -> None:
    global _anthropic
    if _anthropic is not None:
        return
    import anthropic

    _anthropic = anthropic


def _exceptions():
    _import_sdk()
    assert _anthropic is not None
    return (
        _anthropic.APIStatusError,
        _anthropic.APITimeoutError,
        _anthropic.APIConnectionError,
    )


# Anthropic ``max_tokens`` is required. 1024 is enough for the chat UI;
# we can make this per-model later if needed.
_DEFAULT_MAX_TOKENS = 1024

_RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class AnthropicProvider(BaseProvider):
    name = "anthropic"

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self._client: Any | None = None

    def is_configured(self) -> bool:
        return bool(os.environ.get("ANTHROPIC_API_KEY", "").strip())

    def _get_client(self) -> Any:
        if self._client is not None:
            return self._client
        _import_sdk()
        assert _anthropic is not None
        key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
        if not key:
            raise PermanentError("ANTHROPIC_API_KEY is not configured on the server.")
        self._client = _anthropic.AsyncAnthropic(api_key=key)
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
        try:
            response = await client.messages.create(
                model=self.model,
                system=system_prompt,
                messages=messages,
                max_tokens=_DEFAULT_MAX_TOKENS,
                temperature=0.7,
            )
        except Exception as exc:  # noqa: BLE001
            raise _classify(exc) from exc

        text = _extract_text(response.content)
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
        try:
            # ``client.messages.stream`` returns a context manager; we use
            # it via ``async with`` so resources are cleaned up.
            async with client.messages.stream(
                model=self.model,
                system=system_prompt,
                messages=messages,
                max_tokens=_DEFAULT_MAX_TOKENS,
                temperature=0.7,
            ) as stream:
                async for delta in stream.text_stream:
                    text = delta.strip()
                    if text:
                        yield text
        except Exception as exc:  # noqa: BLE001
            raise _classify(exc) from exc


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _classify(exc: Exception) -> Exception:
    """Map an Anthropic SDK exception to RetryableError / PermanentError."""
    APIStatusError, APITimeoutError, APIConnectionError = _exceptions()

    if isinstance(exc, (APITimeoutError, APIConnectionError)):
        return RetryableError(f"Anthropic connection error: {exc}")
    if isinstance(exc, APIStatusError):
        status = getattr(exc, "status_code", None)
        if isinstance(status, int) and status in _RETRYABLE_STATUS:
            return RetryableError(f"Anthropic status {status}: {exc}")
        return PermanentError(f"Anthropic status {status}: {exc}")
    return PermanentError(f"Anthropic error: {exc}")


def _build_messages(message: str, history: list[dict] | None) -> list[dict]:
    """Translate wire-format history into Anthropic's messages format.

    Anthropic requires strict alternation between ``user`` and
    ``assistant``. If the history ends on a user turn and the new turn
    is also user (which Flutter shouldn't do, but defensively), we merge
    the texts so the wire contract still works.
    """
    pairs: list[tuple[str, str]] = []
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
            pairs.append((role, text))
    pairs.append(("user", message))

    # Merge consecutive same-role entries.
    merged: list[tuple[str, str]] = []
    for role, text in pairs:
        if merged and merged[-1][0] == role:
            merged[-1] = (role, merged[-1][1] + "\n\n" + text)
        else:
            merged.append((role, text))

    # Anthropic requires the conversation to start with a user turn. If
    # the first entry is somehow ``assistant`` (malformed wire), drop it.
    while merged and merged[0][0] != "user":
        merged.pop(0)

    # And end with a user turn. The merge above plus the always-appended
    # user turn guarantee this in practice; defensive guard for paranoia.
    if merged and merged[-1][0] != "user":
        merged.append(("user", ""))

    return [{"role": role, "content": text} for role, text in merged]


def _extract_text(content: list[Any]) -> str:
    """Pull text out of an Anthropic ``response.content`` block list.

    Anthropic returns ``content`` as a list of typed blocks (TextBlock,
    ToolUseBlock, etc.). We grab the first TextBlock we find. If there
    are multiple, we concatenate them. Refusals come back as a TextBlock
    with refusal-ish text — we surface them as a regular reply rather
    than treating them as errors, since they're semantically valid
    content.
    """
    parts: list[str] = []
    for block in content or []:
        text = getattr(block, "text", None)
        if isinstance(text, str) and text:
            parts.append(text)
    return "".join(parts).strip()


# IMPORTANT: kept in sync with ``ai.SYSTEM_PROMPT``. See the comment in
# ``ai/providers/gemini.py`` for why this is duplicated.
_SYSTEM_PROMPT_TEXT = (
    "You are OdiAI, a friendly and concise personal AI assistant. "
    "Answer the user's questions clearly and helpfully. If you don't "
    "know the answer, say so honestly rather than inventing facts."
)


register("anthropic", AnthropicProvider)
