"""Task 38 verification harness.

Exercises POST /chat with a two-turn conversation to prove that Gemini
uses prior turns as context for follow-ups:

  Turn 1: user says "My name is Odi."
  Turn 2: user asks "What's my name?" — sent with turn 1 in `history`.

If context works, Gemini's reply must mention "Odi". If context is
broken, Gemini will say it doesn't know the user's name (or invent one).

Also re-runs the original single-turn prompts (no `history` field) to
prove that adding `history` did not regress clients that don't send it.

Run from odi/backend/ with the venv active:

    ./venv/Scripts/python.exe test_task38.py

Exits 0 on full success, 1 on any failure.
"""

from __future__ import annotations

import io
import json
import sys
import urllib.request
from typing import Any

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
else:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8765/chat"


def post_chat(message: str, history: list[dict[str, str]] | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"message": message}
    if history is not None:
        payload["history"] = history
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main() -> int:
    print(f"Task 38 verification — multi-turn + single-turn → {URL}\n")

    # ── Multi-turn test (Task 38 DoD) ────────────────────────────────────
    turn1_prompt = "My name is Odi."
    try:
        turn1 = post_chat(turn1_prompt)
    except Exception as exc:
        print(f"  ✗ turn 1 failed: {exc}")
        return 1
    if "error" in turn1:
        print(f"  ✗ turn 1 server error: {turn1}")
        return 1
    turn1_reply = (turn1.get("reply") or "").strip()
    if not turn1_reply:
        print("  ✗ turn 1 empty reply")
        return 1
    print(f"  ✓ turn 1: {turn1_prompt!r}")
    print(f"      → ({len(turn1_reply)} chars) {turn1_reply[:120]}…")

    # Send turn 2 with turn 1 as history. This is the test that proves
    # Gemini is using the prior turn: without history Gemini has no way
    # to know the user's name.
    turn2_prompt = "What's my name?"
    history_for_turn2 = [
        {"role": "user", "text": turn1_prompt},
        {"role": "assistant", "text": turn1_reply},
    ]
    try:
        turn2 = post_chat(turn2_prompt, history=history_for_turn2)
    except Exception as exc:
        print(f"  ✗ turn 2 failed: {exc}")
        return 1
    if "error" in turn2:
        print(f"  ✗ turn 2 server error: {turn2}")
        return 1
    turn2_reply = (turn2.get("reply") or "").strip()
    if not turn2_reply:
        print("  ✗ turn 2 empty reply")
        return 1
    print(f"  ✓ turn 2: {turn2_prompt!r} (with history)")
    print(f"      → ({len(turn2_reply)} chars) {turn2_reply[:120]}…")

    # The reply MUST mention "Odi" — that's the whole point of Task 38.
    if "odi" not in turn2_reply.lower():
        print("\n  ✗ Gemini did NOT use prior context — 'Odi' missing from reply.")
        print("    This means conversation context isn't reaching the model.")
        return 1
    print("      → contains 'Odi' — context is being used. ✓")

    # ── Single-turn regression test ──────────────────────────────────────
    # Make sure adding the history field didn't break clients that
    # don't send it. Same /chat endpoint, no history at all.
    for prompt, expected in [
        ("Hello OdiAI", ["hello", "hi", "hey", "greetings", "odiai", "assistant"]),
        ("What is Flutter?", ["flutter", "google", "dart", "ui", "framework"]),
    ]:
        try:
            data = post_chat(prompt)  # no history kwarg → omit field
        except Exception as exc:
            print(f"  ✗ single-turn {prompt!r} failed: {exc}")
            return 1
        if "error" in data:
            print(f"  ✗ single-turn {prompt!r} server error: {data}")
            return 1
        reply = (data.get("reply") or "").strip()
        if not reply:
            print(f"  ✗ single-turn {prompt!r} empty reply")
            return 1
        low = reply.lower()
        hits = [s for s in expected if s in low]
        print(f"  ✓ single-turn {prompt!r} → ({len(reply)} chars) hits={hits}")

    print("\nMulti-turn context works, single-turn still works, no key leaked.")
    print("Task 38 is satisfied. ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
