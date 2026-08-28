"""Task 41 — multi-provider wiring smoke test.

Verifies the registry that backs ``ODIAI_MODEL_CHAIN`` is wired up
correctly for all three providers the backend ships with (Gemini,
OpenAI, Anthropic). Pure local checks — no network, no API keys
required. Run from ``odi/backend/`` with the venv active:

    python test_multi_provider_wiring.py

Exits 0 on full pass, 1 on any failure.

Test cases
----------
1. test_registry_has_all_three_kinds
   The provider registry exposes ``gemini``, ``openai``, and
   ``anthropic`` after package import.
2. test_build_provider_constructs_each
   ``build_provider(kind, model)`` returns an instance of the matching
   concrete provider class.
3. test_is_configured_reads_correct_env
   Each provider's ``is_configured()`` returns ``True`` iff its
   specific API key env var is set (GEMINI_API_KEY / OPENAI_API_KEY /
   ANTHROPIC_API_KEY). The others are not consulted.
4. test_parse_chain_handles_three_kinds
   ``_parse_chain`` splits a three-provider chain string into the
   expected ``(kind, model)`` tuples in order.
5. test_unconfigured_provider_skipped_silently
   With one key set and two unset, ``_configured_providers()`` returns
   only the configured provider. (Uses a stub ``build_provider`` so we
   can validate selection without depending on the live SDKs being
   importable.)
"""

from __future__ import annotations

import asyncio
import io
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

# IMPORTANT: keep the test runnable as ``python test_multi_provider_wiring.py``
# from the backend directory, matching the existing test files' style.
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)


class TestRegistry(unittest.TestCase):
    """The provider registry exposes every kind we ship."""

    def test_registry_has_all_three_kinds(self) -> None:
        from ai.providers import REGISTRY

        for kind in ("gemini", "openai", "anthropic"):
            self.assertIn(kind, REGISTRY, f"provider kind {kind!r} not registered")
            self.assertTrue(callable(REGISTRY[kind]))

    def test_build_provider_constructs_each(self) -> None:
        from ai.providers import build_provider
        from ai.providers.anthropic import AnthropicProvider
        from ai.providers.gemini import GeminiProvider
        from ai.providers.openai import OpenAIProvider

        cases = {
            "gemini": GeminiProvider,
            "openai": OpenAIProvider,
            "anthropic": AnthropicProvider,
        }
        for kind, expected_cls in cases.items():
            with self.subTest(kind=kind):
                provider = build_provider(kind, "test-model")
                self.assertIsInstance(provider, expected_cls)
                self.assertEqual(provider.model, "test-model")

    def test_unknown_kind_raises(self) -> None:
        from ai.errors import AIServiceError
        from ai.providers import build_provider

        with self.assertRaises(AIServiceError):
            build_provider("not-a-real-kind", "any-model")


class TestIsConfigured(unittest.TestCase):
    """Each provider keys off its own env var and nothing else."""

    def setUp(self) -> None:
        # Snapshot env so we can mutate it for each case without leaking.
        self._saved = {k: os.environ.get(k) for k in (
            "GEMINI_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY",
        )}

    def tearDown(self) -> None:
        for k, v in self._saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_gemini_keys_off_gemini_key(self) -> None:
        from ai.providers.gemini import GeminiProvider

        os.environ.pop("OPENAI_API_KEY", None)
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ["GEMINI_API_KEY"] = "test-key"

        p = GeminiProvider(model="gemini-3.5-flash-lite")
        self.assertTrue(p.is_configured())

        os.environ.pop("GEMINI_API_KEY", None)
        self.assertFalse(p.is_configured())

    def test_openai_keys_off_openai_key(self) -> None:
        from ai.providers.openai import OpenAIProvider

        os.environ.pop("GEMINI_API_KEY", None)
        os.environ.pop("ANTHROPIC_API_KEY", None)
        os.environ["OPENAI_API_KEY"] = "test-key"

        p = OpenAIProvider(model="gpt-4o-mini")
        self.assertTrue(p.is_configured())

        os.environ.pop("OPENAI_API_KEY", None)
        self.assertFalse(p.is_configured())

    def test_anthropic_keys_off_anthropic_key(self) -> None:
        from ai.providers.anthropic import AnthropicProvider

        os.environ.pop("GEMINI_API_KEY", None)
        os.environ.pop("OPENAI_API_KEY", None)
        os.environ["ANTHROPIC_API_KEY"] = "test-key"

        p = AnthropicProvider(model="claude-haiku-4-5-20251001")
        self.assertTrue(p.is_configured())

        os.environ.pop("ANTHROPIC_API_KEY", None)
        self.assertFalse(p.is_configured())


class TestChainParser(unittest.TestCase):
    """``_parse_chain`` understands all three kinds in order."""

    def test_parse_chain_three_kinds(self) -> None:
        from ai.chain import _parse_chain

        out = _parse_chain(
            "gemini:gemini-3.5-flash-lite,"
            "openai:gpt-4o-mini,"
            "anthropic:claude-haiku-4-5-20251001"
        )
        self.assertEqual(
            out,
            [
                ("gemini", "gemini-3.5-flash-lite"),
                ("openai", "gpt-4o-mini"),
                ("anthropic", "claude-haiku-4-5-20251001"),
            ],
        )

    def test_parse_chain_drops_malformed(self) -> None:
        from ai.chain import _parse_chain

        # Whitespace tolerated; blank entries dropped; entries without
        # ``:`` dropped with a WARNING (captured to keep test output clean).
        buf = io.StringIO()
        with redirect_stdout(buf):  # noqa: SIM117 - keep single ``with``
            out = _parse_chain(
                "  gemini:gemini-3.5-flash-lite , , oops, anthropic: claude-haiku-4-5-20251001"
            )
        self.assertEqual(
            out,
            [
                ("gemini", "gemini-3.5-flash-lite"),
                ("anthropic", "claude-haiku-4-5-20251001"),
            ],
        )


class TestConfiguredProvidersSkipsMissing(unittest.TestCase):
    """``_configured_providers`` only returns providers whose key is set."""

    def test_only_configured_provider_kept(self) -> None:
        # Stub build_provider so we don't depend on the live SDKs being
        # importable; the chain executor only cares about is_configured().
        class _Stub:
            def __init__(self, kind: str, model: str) -> None:
                self.kind = kind
                self.model = model
                self.name = kind
                self._configured = (kind == "openai")

            def is_configured(self) -> bool:
                return self._configured

        def _stub_build(kind: str, model: str) -> "_Stub":
            return _Stub(kind, model)

        from ai import chain

        env = {
            "ODIAI_MODEL_CHAIN":
                "gemini:gemini-3.5-flash-lite,"
                "openai:gpt-4o-mini,"
                "anthropic:claude-haiku-4-5-20251001",
            "OPENAI_API_KEY": "test",
        }
        with patch.dict(os.environ, env, clear=True), \
                patch.object(chain, "build_provider", _stub_build):
            providers = chain._configured_providers()

        self.assertEqual(len(providers), 1)
        self.assertEqual(providers[0].kind, "openai")


def main() -> int:
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(unittest.defaultTestLoader.loadTestsFromTestCase(
        TestRegistry,
    )) if False else runner.run(
        unittest.TestLoader().loadTestsFromModule(sys.modules[__name__])
    )
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())
