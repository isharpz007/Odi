"""Provider chain executor.

Reads the ``ODIAI_MODEL_CHAIN`` env var (default
``"gemini:gemini-3.5-flash-lite"``), instantiates the configured providers
in order, and walks them with automatic fallback on transient errors.

Behavior summary
----------------

``generate_reply``:

    1. Build the configured provider list (skip any whose key is missing).
    2. For each provider, in order, call ``await provider.generate(...)``.
    3. On ``PermanentError``: raise immediately, no fallback.
    4. On ``RetryableError``: log + continue to the next provider.
    5. On success: return the text.
    6. Chain exhausted: raise ``AIServiceError`` carrying the last
       retryable error's detail (so ``main.py`` still produces the same
       ``ai_unavailable`` 502 envelope).

``stream_reply`` is the same loop but with a stricter rule: once a
provider yields its first delta, the chain is locked to that provider
for the rest of the response. Errors that occur *before* any delta is
yielded trigger fallback (silent — no ``ERROR:`` sentinel reaches the
client). Errors after the first delta propagate as ``AIServiceError`` so
``main.py``'s existing wrapper emits the documented ``ERROR: <detail>``
line.

An empty stream (no deltas, no exception) is treated as retryable: the
chain tries the next provider. This guards against a provider that
returns 200 OK with no content for some reason.
"""

from __future__ import annotations

import logging
import os
from typing import AsyncIterator

from ai.errors import (
    AIServiceError,
    PermanentError,
    RetryableError,
)
from ai.providers import build_provider
from ai.providers.base import BaseProvider

logger = logging.getLogger(__name__)

# IMPORTANT: keep the default aligned with the previous single-provider
# behavior (the one this refactor replaces). Changing the default is a
# behavior change for any deployment that doesn't set ``ODIAI_MODEL_CHAIN``.
DEFAULT_CHAIN = "gemini:gemini-3.5-flash-lite"


def _parse_chain(env_value: str) -> list[tuple[str, str]]:
    """Parse ``"kind:model,kind:model,..."`` into ``[(kind, model), ...]``.

    Malformed entries (no colon, blank, etc.) are logged at WARNING and
    dropped. The order of the input is preserved.
    """
    out: list[tuple[str, str]] = []
    for raw in env_value.split(","):
        entry = raw.strip()
        if not entry:
            continue
        if ":" not in entry:
            logger.warning(
                "ODIAI_MODEL_CHAIN entry %r has no ':' — skipping. "
                "Expected 'kind:model'.",
                entry,
            )
            continue
        kind, _, model = entry.partition(":")
        kind = kind.strip()
        model = model.strip()
        if not kind or not model:
            logger.warning(
                "ODIAI_MODEL_CHAIN entry %r is empty on one side of ':' — skipping.",
                entry,
            )
            continue
        out.append((kind, model))
    return out


def _configured_providers() -> list[BaseProvider]:
    """Resolve the chain env var to a list of ready-to-use providers.

    Entries whose provider's ``is_configured()`` returns ``False`` (no
    API key in the environment) are skipped with an INFO log so the
    operator can see why the chain is shorter than they expected.
    """
    chain_env = os.environ.get("ODIAI_MODEL_CHAIN", DEFAULT_CHAIN).strip()
    specs = _parse_chain(chain_env)
    providers: list[BaseProvider] = []
    for kind, model in specs:
        try:
            provider = build_provider(kind, model)
        except AIServiceError as exc:
            logger.warning("ODIAI_MODEL_CHAIN: %s", exc.detail)
            continue
        if not provider.is_configured():
            logger.info(
                "AI provider %s skipped — no API key configured for that kind.",
                kind,
            )
            continue
        providers.append(provider)
    return providers


async def generate_reply(
    message: str,
    history: list[dict] | None = None,
) -> str:
    """Produce a single assistant reply, walking the provider chain on failure."""
    providers = _configured_providers()
    if not providers:
        raise AIServiceError(
            "No AI providers configured. Set ODIAI_MODEL_CHAIN and the corresponding "
            "API key environment variables (GEMINI_API_KEY, OPENAI_API_KEY, "
            "ANTHROPIC_API_KEY, ...)."
        )

    last_error: RetryableError | None = None
    for provider in providers:
        try:
            return await provider.generate(message, history)
        except PermanentError as exc:
            # Auth, validation, safety block — another provider won't help.
            raise AIServiceError(exc.detail) from exc
        except RetryableError as exc:
            logger.info(
                "AI provider %s failed with a retryable error (%s); trying next.",
                provider.name,
                exc.detail,
            )
            last_error = exc
            continue

    raise AIServiceError(last_error.detail if last_error else "No AI provider produced a reply.")


async def stream_reply(
    message: str,
    history: list[dict] | None = None,
) -> AsyncIterator[str]:
    """Stream the assistant reply, walking the chain on pre-token errors.

    Once a provider yields its first non-empty delta, the chain is locked
    to that provider. Subsequent errors propagate as ``AIServiceError`` so
    ``main.py``'s ``event_generator`` emits the documented ``ERROR: ...``
    sentinel — the Flutter client renders that as an error bubble.
    """
    providers = _configured_providers()
    if not providers:
        raise AIServiceError(
            "No AI providers configured. Set ODIAI_MODEL_CHAIN and the corresponding "
            "API key environment variables (GEMINI_API_KEY, OPENAI_API_KEY, "
            "ANTHROPIC_API_KEY, ...)."
        )

    last_error: RetryableError | None = None
    for idx, provider in enumerate(providers):
        first_token_seen = False
        try:
            async for delta in provider.stream(message, history):
                first_token_seen = True
                yield delta
            # Stream ended cleanly. If we got at least one delta, we're
            # done. If the stream was empty (provider returned no
            # content), treat that as retryable and try the next.
            if first_token_seen:
                return
            logger.info(
                "AI provider %s returned an empty stream; trying next provider.",
                provider.name,
            )
            last_error = RetryableError(
                f"Provider {provider.name} returned an empty stream."
            )
        except PermanentError as exc:
            raise AIServiceError(exc.detail) from exc
        except RetryableError as exc:
            # If tokens have already been yielded to the caller, the
            # caller has a partial reply on the screen. Falling back now
            # would produce a confusing "two replies spliced together"
            # UX. Surface the error so main.py emits ERROR: and the
            # client renders an error bubble over the partial text.
            if first_token_seen:
                raise AIServiceError(exc.detail) from exc
            # No tokens yet — silent retry on the next provider. The
            # client never sees the failure.
            logger.info(
                "AI provider %s failed before first token (%s); trying next.",
                provider.name,
                exc.detail,
            )
            last_error = exc
            continue

    raise AIServiceError(
        last_error.detail if last_error else "No AI provider produced a reply."
    )
