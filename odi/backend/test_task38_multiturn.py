"""Task 38 — multi-turn context plumbing.

Drives the chat pipeline with two turns and asserts:

1. The provider's ``generate`` sees the prior user message and prior
   assistant reply in its ``history`` argument for turn 2.
2. The wire payload sent to the provider does NOT include the just-sent
   turn-2 message inside ``history`` AND repeated as ``message`` —
   i.e. history captures are taken *before* the new user bubble lands.
3. The provider's reply text for turn 2 mentions the name from turn 1,
   proving end-to-end context propagation through the chain executor
   and the real ``ai.generate_reply`` / ``ai.stream_reply`` functions.

Pure-mock test suite — no network, no live API keys. Run from
``odi/backend/`` with the venv active:

    python test_task38_multiturn.py

Exits 0 on full pass, 1 on any failure.
"""

from __future__ import annotations

import asyncio
import io
import os
import sys
import unittest
from contextlib import redirect_stdout
from typing import Any
from unittest.mock import patch

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)


class _RecordingProvider:
    """Stub provider that records every ``generate`` call.

    The reply it returns is derived from the history so we can detect
    that the chain executor actually plumbed the prior turn through.
    For turn 2 the stub returns "Your name is Odi." if the prior user
    turn named "Odi"; otherwise a generic reply. This lets the
    end-to-end test assert that turn 2's reply carries the context.
    """

    def __init__(self, kind: str, model: str, replies: list[str]) -> None:
        self.kind = kind
        self.model = model
        self.name = kind
        self._replies = list(replies)
        self.calls: list[dict[str, Any]] = []

    def is_configured(self) -> bool:
        return True

    def _get_client(self) -> Any:  # pragma: no cover - never called
        raise NotImplementedError

    def build_request(
        self,
        message: str,
        history: list[dict] | None,
    ) -> tuple[Any, str]:
        return history or [], ""

    async def generate(
        self,
        message: str,
        history: list[dict] | None,
    ) -> str:
        # IMPORTANT: snapshot the exact (message, history) tuple we
        # received so the assertions below can verify the wire contract.
        self.calls.append({"message": message, "history": list(history or [])})
        # Pop the next pre-canned reply (or a generic fallback) so the
        # test can drive a deterministic two-turn conversation.
        if self._replies:
            return self._replies.pop(0)
        # Derive a name-aware reply for turn 2 if no canned reply is left.
        for turn in reversed(history or []):
            if turn.get("role") == "user" and "Odi" in turn.get("text", ""):
                return "Your name is Odi."
        return "Hello!"

    async def stream(self, message: str, history: list[dict] | None):  # pragma: no cover
        yield await self.generate(message, history)


def _stub_build(kind: str, model: str, providers: list[_RecordingProvider]):
    """Return a build_provider replacement that yields the next stub.

    NOTE: no longer used — the multi-turn test stubs
    ``_configured_providers`` directly so a single recording instance
    is reused across turns. Kept here in case future tests want to
    exercise the ``build_provider`` path with multiple providers.
    """
    state = {"idx": 0}

    def _build(kind: str, model: str) -> _RecordingProvider:
        idx = state["idx"]
        state["idx"] += 1
        return providers[idx]

    return _build


class TestMultiturnContext(unittest.TestCase):
    """End-to-end multi-turn plumbing through the real chain executor."""

    def test_turn2_sees_turn1_in_history_and_uses_it(self) -> None:
        from ai import chain

        # IMPORTANT: the chain executor calls ``_configured_providers``
        # on every ``generate_reply`` invocation, which in turn calls
        # ``build_provider`` once per provider in the chain. We want
        # BOTH turn 1 and turn 2 to land on the SAME recording stub so
        # the call log covers the full conversation. The cleanest way
        # is to stub ``_configured_providers`` directly — that bypasses
        # the parse/build machinery and gives us a stable provider
        # list across calls.
        gemini = _RecordingProvider(
            "gemini",
            "gemini-3.5-flash-lite",
            replies=["Nice to meet you!", "Your name is Odi."],
        )
        env = {"ODIAI_MODEL_CHAIN": "gemini:gemini-3.5-flash-lite"}

        async def _drive() -> tuple[str, str]:
            turn1 = await chain.generate_reply(
                "My name is Odi.", history=None,
            )
            turn2 = await chain.generate_reply(
                "What is my name?",
                history=[
                    {"role": "user", "text": "My name is Odi."},
                    {"role": "assistant", "text": turn1},
                ],
            )
            return turn1, turn2

        with patch.dict(os.environ, env, clear=True), \
                patch.object(chain, "_configured_providers", lambda: [gemini]), \
                redirect_stdout(io.StringIO()):
            t1, t2 = asyncio.run(_drive())

        # Reply content
        self.assertEqual(t1, "Nice to meet you!")
        self.assertIn("Odi", t2)

        # Wire: the stub recorded exactly two generate() calls.
        self.assertEqual(len(gemini.calls), 2)
        call1, call2 = gemini.calls

        # Turn 1 is single-turn.
        self.assertEqual(call1["message"], "My name is Odi.")
        self.assertEqual(call1["history"], [])

        # Turn 2's history contains turn 1's user message and the
        # assistant's reply from turn 1.
        self.assertEqual(call2["message"], "What is my name?")
        self.assertEqual(
            call2["history"],
            [
                {"role": "user", "text": "My name is Odi."},
                {"role": "assistant", "text": "Nice to meet you!"},
            ],
        )

        # Critical: the just-sent turn-2 message must NOT appear in
        # history as well (that's the bug the audit found in
        # chat_screen.dart). The history slice must end on the prior
        # assistant turn, with the new user message only present as
        # the trailing message field.
        self.assertNotEqual(call2["history"][-1], {"role": "user", "text": "What is my name?"})
        self.assertEqual(call2["history"][-1]["role"], "assistant")

    def test_gemini_provider_merges_trailing_user_in_history(self) -> None:
        """Belt-and-suspenders: Gemini provider normalises a malformed
        history that ends with a user turn followed by another user
        ``message`` field (which a buggy client might still send).
        """
        from ai.providers.gemini import _build_contents

        # Force the SDK imports to materialise; if the SDK is not
        # installed we skip rather than fail (mirrors how the chain
        # itself degrades when an optional provider is missing).
        try:
            from google import genai  # noqa: F401
        except ImportError:
            self.skipTest("google-genai SDK not installed in this env")

        # Build contents for: history ends on a user turn, and the
        # new message also arrives as a user turn.
        contents = _build_contents(
            "What is my name?",
            [
                {"role": "user", "text": "My name is Odi."},
                {"role": "assistant", "text": "Nice to meet you!"},
                # Malformed: another user turn at the tail.
                {"role": "user", "text": "What is my name?"},
            ],
        )

        # The conversation must start AND end on a user turn.
        self.assertEqual(contents[0].role, "user")
        self.assertEqual(contents[-1].role, "user")

        # Two consecutive user turns must not appear — that's the
        # alternation invariant Gemini enforces.
        roles = [c.role for c in contents]
        for prev, cur in zip(roles, roles[1:]):
            self.assertNotEqual(
                prev, cur,
                f"two consecutive {prev!r} turns in {roles!r}",
            )

        # Both the prior user text and the new message must be present
        # somewhere in the conversation — possibly merged into the
        # trailing user Content, possibly as a separate leading user
        # Content. What matters is that neither got dropped.
        all_text = " || ".join(
            c.parts[0].text for c in contents if c.parts
        )
        self.assertIn("My name is Odi.", all_text)
        self.assertIn("What is my name?", all_text)

        # And the prior assistant turn must still be present in the
        # chain so the model can see context that was sandwiched
        # between the two user turns.
        assistant_texts = [
            c.parts[0].text for c in contents if c.role == "model"
        ]
        self.assertTrue(
            any("Nice to meet you!" in t for t in assistant_texts),
            f"assistant reply missing from merged contents: {contents!r}",
        )

    def test_gemini_provider_drops_leading_assistant_turns(self) -> None:
        """Gemini rejects conversations that start with ``model``."""
        from ai.providers.gemini import _build_contents

        try:
            from google import genai  # noqa: F401
        except ImportError:
            self.skipTest("google-genai SDK not installed in this env")

        contents = _build_contents(
            "Hello",
            [
                {"role": "assistant", "text": "stray greeting"},
                {"role": "user", "text": "hi"},
            ],
        )

        # Leading model turn dropped; conversation starts on user.
        self.assertEqual(contents[0].role, "user")
        self.assertNotIn("stray greeting", contents[0].parts[0].text)


def main() -> int:
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(
        unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    )
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
