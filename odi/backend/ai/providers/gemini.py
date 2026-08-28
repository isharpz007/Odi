"""Google Gemini provider.

Extracted from the original ``ai.py`` (Tasks 31-34, 38, 38½). The provider
wraps ``google-genai`` and translates between:

    - Wire format (Flutter):  ``{"role": "user"|"assistant", "text": ...}``
    - Gemini SDK format:      ``Content(role="user"|"model", parts=[Part(...)])``

The system prompt is supplied via ``GenerateContentConfig(system_instruction=...)``.

Error classification (per the plan):

    RetryableError: HTTP 429 / 5xx, network-layer failures.
    PermanentError: 400 / 401 / 403 / 404, safety blocks, empty responses.

We do not implement a separate ``RetryableError`` for safety blocks because
those manifest as an empty ``response.text`` — same end-state as a
content-empty reply, which we already treat as permanent.
"""

from __future__ import annotations

import logging
import os
from typing import Any, AsyncIterator

from ai.errors import AIServiceError, PermanentError, RetryableError
from ai.providers import register
from ai.providers.base import BaseProvider

logger = logging.getLogger(__name__)

# Lazy imports so the absence of the SDK doesn't crash the chain at import
# time. ``_import_sdk`` is called inside ``_get_client`` on first use.
_genai = None
_genai_errors = None
_genai_types = None


def _import_sdk() -> None:
    global _genai, _genai_errors, _genai_types
    if _genai is not None:
        return
    from google import genai
    from google.genai import errors as genai_errors
    from google.genai import types as genai_types

    _genai = genai
    _genai_errors = genai_errors
    _genai_types = genai_types


# Gemini status codes that should trigger fallback. Anything else (400,
# 401, 403, 404, ...) is permanent — switching to another model won't fix
# a bad request or a missing API key.
_RETRYABLE_CODES = {429, 500, 501, 502, 503, 504}


class GeminiProvider(BaseProvider):
    name = "gemini"

    def __init__(self, model: str) -> None:
        super().__init__(model)
        self._client: Any | None = None

    def is_configured(self) -> bool:
        return bool(os.environ.get("GEMINI_API_KEY", "").strip())

    def _get_client(self) -> Any:
        if self._client is not None:
            return self._client
        _import_sdk()
        assert _genai is not None
        key = os.environ.get("GEMINI_API_KEY", "").strip()
        if not key:
            # Defensive: ``is_configured`` should have already filtered us
            # out. If we somehow get here, surface a clean permanent error.
            raise PermanentError("GEMINI_API_KEY is not configured on the server.")
        self._client = _genai.Client(api_key=key)
        return self._client

    def build_request(
        self,
        message: str,
        history: list[dict] | None,
    ) -> tuple[Any, str]:
        # Lazy import: the SDK may not be installed in every environment.
        _import_sdk()
        assert _genai_types is not None
        return _build_contents(message, history), _SYSTEM_PROMPT_TEXT

    async def generate(self, message: str, history: list[dict] | None) -> str:
        _import_sdk()
        client = self._get_client()
        contents, system_prompt = self.build_request(message, history)
        config = _make_config(system_prompt)
        try:
            response = await client.aio.models.generate_content(
                model=self.model,
                contents=contents,
                config=config,
            )
        except _genai_errors.APIError as exc:  # type: ignore[name-defined]
            raise _classify_api_error(exc) from exc
        except Exception as exc:  # noqa: BLE001 - SDK wraps transport failures in many classes
            raise PermanentError(f"AI service unavailable: {exc}") from exc

        text = (response.text or "").strip()
        if not text:
            # Safety block or genuinely-empty reply. Either way, switching
            # providers won't help.
            raise PermanentError("The AI returned an empty response. Please try again.")
        return text

    async def stream(
        self,
        message: str,
        history: list[dict] | None,
    ) -> AsyncIterator[str]:
        _import_sdk()
        client = self._get_client()
        contents, system_prompt = self.build_request(message, history)
        config = _make_config(system_prompt)
        try:
            stream = await client.aio.models.generate_content_stream(
                model=self.model,
                contents=contents,
                config=config,
            )
        except _genai_errors.APIError as exc:  # type: ignore[name-defined]
            raise _classify_api_error(exc) from exc
        except Exception as exc:  # noqa: BLE001
            raise PermanentError(f"AI service unavailable: {exc}") from exc

        async for chunk in stream:
            text = (chunk.text or "").strip()
            if text:
                yield text


# ---------------------------------------------------------------------------
# Helpers — kept module-level so they can be unit-tested without
# instantiating the provider.
# ---------------------------------------------------------------------------


def _classify_api_error(exc: Any) -> AIServiceError:
    """Map a Gemini SDK ``APIError`` to Retryable/Permanent."""
    code = getattr(exc, "code", None)
    detail = str(exc)
    if isinstance(code, int) and code in _RETRYABLE_CODES:
        return RetryableError(f"Gemini API error ({code}): {detail}")
    # Anything else (400/401/403/404 or unknown code) is permanent.
    return PermanentError(f"Gemini API error ({code}): {detail}")


def _build_contents(message: str, history: list[dict] | None) -> list[Any]:
    """Translate wire-format history into Gemini ``Content`` list.

    Wire invariants we enforce before handing the list to Gemini:

    1. Roles are translated (``assistant`` -> ``model``) and unknown
       roles are dropped.
    2. The first turn must be a ``user`` turn — Gemini rejects
       conversations that start with ``model``.
    3. We never emit two consecutive same-role turns. If history ends
       on a ``user`` turn (e.g. a buggy client sent a history slice
       that already includes the message the client is about to send),
       we merge the trailing text into the appended message so the
       conversation ends on exactly one user turn.
    4. Empty texts are skipped so we don't hand Gemini a meaningless
       empty ``Part``.
    """
    _import_sdk()
    assert _genai_types is not None
    raw: list[tuple[str, str]] = []
    if history:
        for turn in history:
            if not isinstance(turn, dict):
                continue
            role_raw = turn.get("role")
            text = turn.get("text")
            if not isinstance(text, str) or not text:
                continue
            if role_raw == "user":
                raw.append(("user", text))
            elif role_raw == "assistant":
                raw.append(("model", text))
            else:
                # Unknown roles are dropped silently.
                continue

    # Defensive: merge a trailing user turn into the new message so we
    # never end up with two consecutive user turns. Flutter's
    # ``_dispatchUserSend`` captures history before appending the new
    # user bubble, so this is a belt-and-suspenders pass for any
    # client that forgets.
    if raw and raw[-1][0] == "user":
        last_user_text = raw[-1][1]
        raw.pop()
        merged_message = f"{last_user_text}\n\n{message}"
    else:
        merged_message = message

    # Defensive: Gemini requires the conversation to start with a user
    # turn. If the malformed wire starts with ``model``, drop leading
    # model turns until we find a user turn.
    while raw and raw[0][0] != "user":
        raw.pop(0)

    contents: list[Any] = [
        _genai_types.Content(role=role, parts=[_genai_types.Part(text=text)])
        for role, text in raw
    ]
    contents.append(
        _genai_types.Content(
            role="user",
            parts=[_genai_types.Part(text=merged_message)],
        )
    )
    return contents


# IMPORTANT: kept in sync with ``ai.SYSTEM_PROMPT`` so each provider sends
# the same system text. We can't import the constant directly because it
# would create a circular import (``ai`` -> ``ai.chain`` -> ``ai.providers.gemini``
# -> ``ai.errors``). The duplicate is intentional; update both if you
# change the voice.
_SYSTEM_PROMPT_TEXT = (
    "You are OdiAI, a friendly and concise personal AI assistant. "
    "Answer the user's questions clearly and helpfully. If you don't "
    "know the answer, say so honestly rather than inventing facts."
)


def _make_config(system_prompt: str) -> Any:
    """Build the Gemini ``GenerateContentConfig`` for a request."""
    _import_sdk()
    assert _genai_types is not None
    return _genai_types.GenerateContentConfig(
        system_instruction=system_prompt,
        # Default temperature is 1.0; we lower it slightly so replies stay
        # focused and predictable. Tunable later without touching any
        # other file.
        temperature=0.7,
    )


register("gemini", GeminiProvider)
