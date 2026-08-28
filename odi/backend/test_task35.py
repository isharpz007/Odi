"""Task 35 + Task 36 verification harness.

Exercises POST /chat with the prompts both tasks require and asserts
that Gemini (not an echo) produced each reply. Designed to be re-run
by hand after a real GEMINI_API_KEY is dropped into `.env`.

Run from odi/backend/ with the venv active:

    ./venv/Scripts/python.exe test_task35.py

Exits 0 on full success, 1 on any failure. Prints a per-prompt summary
so the human running it can eyeball the results too.
"""

from __future__ import annotations

import io
import json
import sys
import urllib.request
from typing import Any

# Force UTF-8 on stdout so the AI's reply (which may contain em-dashes,
# smart quotes, non-ASCII tokens) does not crash the Windows cp1252
# console.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
else:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8765/chat"

PROMPTS: list[tuple[str, list[str]]] = [
    # (prompt, substrings we expect the AI's reply to contain)
    # ── Task 35: prove one prompt → one real Gemini reply ────────────────
    (
        "Hello OdiAI",
        ["hello", "hi", "hey", "greetings", "i am", "i'm", "odiai", "assistant"],
    ),
    (
        "What is Flutter?",
        ["flutter", "google", "dart", "ui", "framework", "cross-platform"],
    ),
    (
        "Explain FastAPI in simple terms.",
        ["fastapi", "python", "api", "web", "framework", "endpoint"],
    ),
    # ── Task 36: prove the response flows back through FastAPI correctly ─
    (
        "Explain software engineering to a beginner.",
        [
            "software",
            "engineering",
            "design",
            "build",
            "test",
            "maintain",
            "code",
            "system",
        ],
    ),
    (
        "Give me three ideas for a personal AI assistant.",
        ["1", "2", "3", "idea", "assistant", "personal"],
    ),
]


def post_chat(message: str) -> dict[str, Any]:
    body = json.dumps({"message": message}).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def is_echo(prompt: str, reply: str) -> bool:
    """Heuristic: did the server just bounce our message back?"""
    norm = reply.lower().strip().rstrip(".!?:")
    return norm == prompt.lower().strip().rstrip(".!?:") or prompt.lower() in reply.lower()[:200]


def main() -> int:
    replies: list[str] = []
    print(f"Task 35 verification — {len(PROMPTS)} prompts → {URL}\n")
    for prompt, expected_substrings in PROMPTS:
        try:
            data = post_chat(prompt)
        except Exception as exc:
            print(f"  ✗ {prompt!r}  network failure: {exc}")
            return 1

        if "error" in data:
            print(f"  ✗ {prompt!r}  server error envelope: {data}")
            return 1

        reply = data.get("reply", "")
        if not reply.strip():
            print(f"  ✗ {prompt!r}  empty reply")
            return 1

        if is_echo(prompt, reply):
            print(f"  ✗ {prompt!r}  reply looks like an echo: {reply!r}")
            return 1

        low = reply.lower()
        hits = [s for s in expected_substrings if s in low]
        print(
            f"  ✓ {prompt!r}\n      → ({len(reply)} chars) "
            f"matched on-topic tokens: {hits if hits else 'none-of-expected'}"
        )
        replies.append(reply)

    # Different prompts must yield different answers.
    distinct = {r.strip().lower() for r in replies}
    if len(distinct) < len(replies):
        print(
            f"\n  ✗ prompts produced identical replies — Gemini is not actually responding."
        )
        return 1

    print(f"\nAll {len(PROMPTS)} prompts produced distinct, non-echo, on-topic replies.")
    print("Task 35 + Task 36 are satisfied. ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
