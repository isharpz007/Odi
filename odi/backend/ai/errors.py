"""Typed exceptions for the AI service layer.

Three exception classes form the contract between providers and the chain
executor:

    AIServiceError     - the umbrella. ``main.py`` catches this and maps to
                         the documented ``ai_unavailable`` 502 envelope.
    RetryableError     - subclass of AIServiceError. The chain executor
                         catches this and tries the next provider. Use for
                         transient failures: HTTP 429, 5xx, network errors.
    PermanentError     - subclass of AIServiceError. The chain executor
                         raises immediately without trying subsequent
                         providers. Use for failures that won't be fixed by
                         switching providers: auth (401/403), validation
                         (400), not found (404), empty responses, safety
                         blocks.

Each provider is responsible for wrapping its SDK's native exceptions in
one of these two subclasses before they leave the provider boundary. The
chain executor therefore never imports ``openai`` or ``anthropic``
exception types directly, which keeps the executor small and the provider
isolation tight.
"""

from __future__ import annotations


class AIServiceError(Exception):
    """Raised when the AI layer cannot produce a reply.

    ``main.py`` catches this and maps to the documented
    ``{ "error": "ai_unavailable", "detail": ... }`` envelope so the
    Flutter client surfaces a friendly error bubble.
    """

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


class RetryableError(AIServiceError):
    """A transient failure: another provider in the chain may succeed.

    Examples: HTTP 429 (rate limit), HTTP 5xx (upstream server error),
    network/timeout errors. The chain executor catches this and tries the
    next configured provider.
    """


class PermanentError(AIServiceError):
    """A non-transient failure: another provider won't help.

    Examples: HTTP 400 (bad request), 401/403 (auth), 404 (model not found),
    empty / safety-blocked responses. The chain executor raises this
    immediately without trying subsequent providers.
    """
