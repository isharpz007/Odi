"""Provider registry and factory.

Each provider module registers a concrete ``BaseProvider`` subclass by
calling ``register()``. The chain executor uses ``build_provider(spec)`` to
turn a ``"kind:model"`` chain entry into a configured provider instance.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from ai.errors import AIServiceError

if TYPE_CHECKING:
    from ai.providers.base import BaseProvider

logger = logging.getLogger(__name__)

# Map of provider kind -> BaseProvider subclass. Populated by each
# provider module on import via ``register()``.
REGISTRY: dict[str, type["BaseProvider"]] = {}


def register(kind: str, cls: type["BaseProvider"]) -> None:
    """Register a concrete provider class under ``kind`` (e.g. ``"gemini"``).

    Called at module import time by each provider module so the chain
    executor can find them without hardcoded imports. Calling ``register``
    with the same ``kind`` twice replaces the previous registration;
    this is intentional for test overrides.
    """
    REGISTRY[kind] = cls


def build_provider(kind: str, model: str) -> "BaseProvider":
    """Construct a provider instance by kind + model id.

    Raises ``AIServiceError`` if the kind is unknown. The caller (chain
    executor) is responsible for filtering by ``is_configured()`` before
    invoking the provider.
    """
    cls = REGISTRY.get(kind)
    if cls is None:
        raise AIServiceError(
            f"Unknown AI provider kind '{kind}'. "
            f"Registered: {sorted(REGISTRY.keys())}."
        )
    return cls(model=model)


# Eagerly import the built-in providers so they self-register on package
# import. Wrapped in try/except so a missing optional SDK doesn't take
# down the whole backend (the chain skips unconfigured providers anyway,
# but the module-level import is the moment we'd actually fail).
def _import_providers() -> None:
    for module_name in ("ai.providers.gemini", "ai.providers.openai", "ai.providers.anthropic"):
        try:
            __import__(module_name)
        except ImportError as exc:
            logger.info(
                "Provider module %s not available (%s) — that provider kind will be unavailable.",
                module_name,
                exc,
            )


_import_providers()
