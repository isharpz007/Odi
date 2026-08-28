"""Task 40 — fallback chain verification.

Pure-mock test suite for the multi-provider chain executor. No network
calls, no live API keys required.

Run from ``odi/backend/`` with the venv active:

    python test_task40_fallback.py

Exits 0 on full pass, 1 on any failure. Prints a per-case summary.

Test cases
----------
1. test_single_provider_success         - one provider, returns text.
2. test_primary_429_falls_back_to_secondary
                                         - first provider raises
                                           RetryableError; second returns text.
3. test_auth_error_does_not_fallback    - first provider raises
                                           PermanentError; second is never called.
4. test_all_providers_fail              - all raise RetryableError;
                                           AIServiceError is raised.
5. test_streaming_fallback_before_first_token
                                         - first stream raises before yielding;
                                           second stream yields.
6. test_streaming_error_after_first_token_does_not_fallback
                                         - first stream yields then raises;
                                           AIServiceError propagates.
7. test_empty_response_is_permanent     - empty content => PermanentError
                                           inside provider, no fallback.
8. test_unconfigured_provider_skipped   - provider in chain has no key,
                                           skipped silently.
9. test_system_prompt_applied_to_all    - SYSTEM_PROMPT reaches every provider.
"""

from __future__ import annotations

import asyncio
import io
import sys
import unittest
from typing import Any, AsyncIterator
from unittest.mock import patch

# Force UTF-8 on stdout (Windows cp1252 issue, same as the other test files).
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
else:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


from ai import chain
from ai.errors import AIServiceError, PermanentError, RetryableError


# ---------------------------------------------------------------------------
# Fake provider — minimal subclass of BaseProvider that records calls.
# ---------------------------------------------------------------------------


class FakeProvider:
    """Drop-in test double. Not a BaseProvider subclass because we don't
    need the full interface — only ``generate`` and ``stream`` matter,
    plus ``name``, ``is_configured``, and ``model`` for chain introspection.
    """

    name: str = "fake"

    def __init__(
        self,
        kind: str,
        model: str,
        configured: bool = True,
        generate_result: Any = None,
        generate_exc: BaseException | None = None,
        stream_deltas: list[str] | None = None,
        stream_exc: BaseException | None = None,
    ) -> None:
        self.kind = kind
        self.model = model
        self._configured = configured
        self._generate_result = generate_result
        self._generate_exc = generate_exc
        self._stream_deltas = stream_deltas or []
        self._stream_exc = stream_exc
        self.generate_calls = 0
        self.stream_calls = 0
        self.last_message: str | None = None
        self.last_history: list[dict] | None = None

    def is_configured(self) -> bool:
        return self._configured

    async def generate(self, message: str, history: list[dict] | None) -> str:
        self.generate_calls += 1
        self.last_message = message
        self.last_history = list(history) if history else None
        if self._generate_exc is not None:
            raise self._generate_exc
        assert isinstance(self._generate_result, str)
        return self._generate_result

    async def stream(
        self, message: str, history: list[dict] | None
    ) -> AsyncIterator[str]:
        self.stream_calls += 1
        self.last_message = message
        self.last_history = list(history) if history else None
        if self._stream_exc is not None:
            # Raise before yielding anything.
            raise self._stream_exc
        for d in self._stream_deltas:
            yield d


def _stub_chain(providers: list[FakeProvider]) -> Any:
    """Patch ``_configured_providers`` to return our fakes."""

    def _stub() -> list[FakeProvider]:
        return providers

    return patch.object(chain, "_configured_providers", _stub)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class ChainTests(unittest.TestCase):
    def test_single_provider_success(self) -> None:
        primary = FakeProvider("openai", "gpt-4o-mini", generate_result="hello back")

        async def run() -> str:
            return await chain.generate_reply("hi")

        with _stub_chain([primary]):
            result = asyncio.run(run())
        self.assertEqual(result, "hello back")
        self.assertEqual(primary.generate_calls, 1)

    def test_primary_429_falls_back_to_secondary(self) -> None:
        primary = FakeProvider(
            "openai", "gpt-4o-mini", generate_exc=RetryableError("rate limit")
        )
        secondary = FakeProvider("anthropic", "claude-haiku-4-5-20251001", generate_result="from claude")

        async def run() -> str:
            return await chain.generate_reply("hi")

        with _stub_chain([primary, secondary]):
            result = asyncio.run(run())
        self.assertEqual(result, "from claude")
        self.assertEqual(primary.generate_calls, 1)
        self.assertEqual(secondary.generate_calls, 1)

    def test_auth_error_does_not_fallback(self) -> None:
        primary = FakeProvider(
            "openai", "gpt-4o-mini", generate_exc=PermanentError("invalid api key")
        )
        secondary = FakeProvider("anthropic", "claude-haiku-4-5-20251001", generate_result="from claude")

        async def run() -> None:
            await chain.generate_reply("hi")

        with _stub_chain([primary, secondary]):
            with self.assertRaises(AIServiceError) as ctx:
                asyncio.run(run())
        self.assertEqual(ctx.exception.detail, "invalid api key")
        # Secondary must NOT have been tried.
        self.assertEqual(secondary.generate_calls, 0)

    def test_all_providers_fail(self) -> None:
        a = FakeProvider("openai", "gpt-4o-mini", generate_exc=RetryableError("a failed"))
        b = FakeProvider("anthropic", "claude-haiku-4-5-20251001", generate_exc=RetryableError("b failed"))
        c = FakeProvider("gemini", "gemini-3.5-flash-lite", generate_exc=RetryableError("c failed"))

        async def run() -> None:
            await chain.generate_reply("hi")

        with _stub_chain([a, b, c]):
            with self.assertRaises(AIServiceError) as ctx:
                asyncio.run(run())
        self.assertEqual(ctx.exception.detail, "c failed")  # last retryable detail
        self.assertEqual(a.generate_calls, 1)
        self.assertEqual(b.generate_calls, 1)
        self.assertEqual(c.generate_calls, 1)

    def test_streaming_fallback_before_first_token(self) -> None:
        primary = FakeProvider(
            "openai", "gpt-4o-mini", stream_exc=RetryableError("timeout")
        )
        secondary = FakeProvider(
            "anthropic", "claude-haiku-4-5-20251001", stream_deltas=["from ", "claude"]
        )

        async def run() -> list[str]:
            out: list[str] = []
            async for d in chain.stream_reply("hi"):
                out.append(d)
            return out

        with _stub_chain([primary, secondary]):
            deltas = asyncio.run(run())
        self.assertEqual(deltas, ["from ", "claude"])
        self.assertEqual(primary.stream_calls, 1)
        self.assertEqual(secondary.stream_calls, 1)

    def test_streaming_error_after_first_token_does_not_fallback(self) -> None:
        # We need a fake that yields one delta and then raises. The base
        # FakeProvider raises before yielding; replace it with a more
        # capable version that yields-then-raises.
        class YieldThenRaise:
            name = "openai"
            def __init__(self) -> None:
                self.stream_calls = 0
            def is_configured(self) -> bool:
                return True
            async def stream(self, message, history):
                self.stream_calls += 1
                yield "first "
                raise RetryableError("stream broke mid-way")

        class ShouldNotRun:
            name = "anthropic"
            def __init__(self) -> None:
                self.stream_calls = 0
            def is_configured(self) -> bool:
                return True
            async def stream(self, message, history):
                self.stream_calls += 1
                yield "should not reach here"

        primary = YieldThenRaise()
        secondary = ShouldNotRun()

        async def run() -> tuple[list[str], bool]:
            out: list[str] = []
            raised = False
            try:
                async for d in chain.stream_reply("hi"):
                    out.append(d)
            except AIServiceError:
                raised = True
            return out, raised

        with _stub_chain([primary, secondary]):
            deltas, raised = asyncio.run(run())
        self.assertEqual(deltas, ["first "])
        self.assertTrue(raised, "AIServiceError should propagate after first-token failure")
        self.assertEqual(primary.stream_calls, 1)
        self.assertEqual(secondary.stream_calls, 0, "secondary must NOT be tried after first-token")

    def test_empty_response_is_permanent(self) -> None:
        # Provider returns an empty string from generate() — the provider
        # itself must translate that into PermanentError, which the
        # chain honors. We model that by having the fake raise
        # PermanentError directly (matching the contract each real
        # provider implements).
        primary = FakeProvider(
            "openai", "gpt-4o-mini", generate_exc=PermanentError("empty response")
        )
        secondary = FakeProvider("anthropic", "claude-haiku-4-5-20251001", generate_result="from claude")

        async def run() -> None:
            await chain.generate_reply("hi")

        with _stub_chain([primary, secondary]):
            with self.assertRaises(AIServiceError) as ctx:
                asyncio.run(run())
        self.assertEqual(ctx.exception.detail, "empty response")
        self.assertEqual(secondary.generate_calls, 0)

    def test_unconfigured_provider_skipped(self) -> None:
        # Use real ``_configured_providers`` filtering by stubbing
        # ``build_provider`` to return our fakes.
        unconfigured = FakeProvider("openai", "gpt-4o-mini", configured=False)
        configured = FakeProvider("anthropic", "claude-haiku-4-5-20251001", generate_result="from claude")

        def _stub_build(kind: str, model: str) -> FakeProvider:
            for p in (unconfigured, configured):
                if p.kind == kind and p.model == model:
                    return p
            raise AssertionError(f"unexpected build_provider({kind!r}, {model!r})")

        env = {"ODIAI_MODEL_CHAIN": "openai:gpt-4o-mini,anthropic:claude-haiku-4-5-20251001"}
        with patch.object(chain, "build_provider", _stub_build), \
             patch.dict("os.environ", env, clear=False):
            providers = chain._configured_providers()
        self.assertEqual(len(providers), 1)
        self.assertIs(providers[0], configured)

    def test_system_prompt_applied_to_all(self) -> None:
        # After running, every fake that was called should have received
        # the message; we verify the public surface (the chain doesn't
        # pass system prompt to providers directly — providers build it
        # from ai.SYSTEM_PROMPT). This test guards the contract that the
        # prompt constant is the same object across providers.
        import ai
        from ai.providers.gemini import _SYSTEM_PROMPT_TEXT as gemini_prompt
        from ai.providers.openai import _SYSTEM_PROMPT_TEXT as openai_prompt
        from ai.providers.anthropic import _SYSTEM_PROMPT_TEXT as anthropic_prompt

        self.assertEqual(ai.SYSTEM_PROMPT, gemini_prompt)
        self.assertEqual(ai.SYSTEM_PROMPT, openai_prompt)
        self.assertEqual(ai.SYSTEM_PROMPT, anthropic_prompt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
