"""Abstract base class for AI providers.

A provider knows how to:

    1. Tell us whether it has the API key it needs (``is_configured``).
    2. Lazily build its SDK client (``_get_client``).
    3. Translate the wire-format ``message + history`` into its SDK's
       native request shape, plus the system prompt (``build_request``).
    4. Send a non-streaming request and return text (``generate``).
    5. Stream text deltas as an async iterator (``stream``).

The provider is also responsible for translating any SDK exception into
either ``RetryableError`` or ``PermanentError`` from ``ai.errors`` so the
chain executor can decide whether to try the next provider.

The chain executor never imports provider SDK exception types.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, AsyncIterator, ClassVar


class BaseProvider(ABC):
    """Base class for all AI providers."""

    # Short identifier used in ``ODIAI_MODEL_CHAIN`` entries and in logs
    # (e.g. ``"gemini"``, ``"openai"``, ``"anthropic"``). Subclasses must
    # set this.
    name: ClassVar[str] = ""

    def __init__(self, model: str) -> None:
        self.model = model

    @abstractmethod
    def is_configured(self) -> bool:
        """Return True iff this provider has the API key it needs.

        Must not require the SDK to be importable; it should only inspect
        environment variables. This lets the chain executor filter
        unconfigured providers without ever importing their SDK.
        """

    @abstractmethod
    def _get_client(self) -> Any:
        """Return a lazily-constructed SDK client.

        The first call constructs and caches the client. Subsequent calls
        return the cached instance. Subclasses should call this from
        ``generate`` / ``stream`` rather than constructing the client
        themselves so SDK init happens on first use, not at import time.
        """

    @abstractmethod
    def build_request(
        self,
        message: str,
        history: list[dict] | None,
    ) -> tuple[Any, str]:
        """Translate wire-format ``message`` + ``history`` into SDK payload.

        Returns a ``(payload, system_prompt)`` tuple. The payload is opaque
        to the chain executor — providers may use a dict, a typed object,
        whatever the SDK wants. The system prompt is passed through so a
        provider that supports a top-level ``system`` field (Anthropic) can
        apply it separately from the messages list.
        """

    @abstractmethod
    async def generate(self, message: str, history: list[dict] | None) -> str:
        """Send a non-streaming request, return the assistant text.

        Implementations must:
            - Apply the system prompt.
            - Translate wire history into the SDK's native message format.
            - Wrap SDK exceptions in ``RetryableError`` or ``PermanentError``.
            - Treat an empty response as ``PermanentError`` so the chain
              does not retry — an empty reply is a content issue, not a
              transport issue.
        """

    @abstractmethod
    def stream(self, message: str, history: list[dict] | None) -> AsyncIterator[str]:
        """Return an async iterator of text deltas.

        Implementations must:
            - Apply the system prompt.
            - Wrap SDK exceptions in ``RetryableError`` or ``PermanentError``.
            - Yield only non-empty stripped deltas; the chain executor
              relies on this invariant to count the "first token" event
              that locks the provider for the rest of the response.
        """
