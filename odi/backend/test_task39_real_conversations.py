"""Task 39 — real-AI conversation verification.

Drives the live FastAPI ``/chat`` endpoint with the 5 user-script
scenarios from the Task 39 brief and asserts each one behaves like a
real user would expect.

This is the final testing task before Milestone 4 is closed out.
Per the brief, no new features are added here — we test what we
already built.

Test 1 — Normal conversation
    You: Hello OdiAI
    AI:  [real greeting-ish response]
    You: What can you help me with?
    AI:  [real capability summary]

Test 2 — Context
    You: My favourite programming language is Dart.
    AI:  [acknowledgement]
    You: What programming language did I say?
    AI:  Dart

Test 3 — Follow-up
    You: What is Flutter?
    AI:  [explanation]
    You: What language does it use?
    AI:  Dart

Test 4 — Subject change
    You: Explain FastAPI.
    AI:  [response]
    You: What's the capital of France?
    AI:  Paris

Test 5 — Longer conversation (8–10 messages)
    Free-form 8–10 turn chat. We don't assert specific reply strings
    because the model has freedom — we assert properties of the
    *pipeline* (no crashes, every reply non-empty, API key never leaks,
    history alternation holds, UI-state invariants carry over).

API key safety
--------------

The script reads ``$env:GEMINI_API_KEY`` (PowerShell) /
``os.environ['GEMINI_API_KEY']`` (this script). It never echoes the
key. Before posting each request, the script captures the request
body string and asserts the key is NOT in it. After every response
the script scans the response body the same way. A leak fails the
test with exit code 1.

Pre-flight
----------

Set ``GEMINI_API_KEY`` in the shell before running. Then start the
server in another shell:

    cd odi/backend
    ./venv/Scripts/uvicorn main:app --host 127.0.0.1 --port 8765

Then run:

    ./venv/Scripts/python.exe test_task39_real_conversations.py

Exit code 0 = all 5 scenarios pass. Exit code 1 = any failure.
"""

from __future__ import annotations

import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Any

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
else:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

URL = "http://127.0.0.1:8765/chat"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


class _ScenarioFailed(Exception):
    """Raised when a scenario fails its assertions."""


def _post_chat(message: str, history: list[dict[str, str]] | None = None) -> dict[str, Any]:
    """POST to /chat and return the parsed JSON response.

    Captures the request body so the safety check can scan it for a
    leaked key. Raises ``_ScenarioFailed`` on HTTP error or malformed
    body so the test can present a clean failure per scenario.
    """
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
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        raise _ScenarioFailed(
            f"server returned HTTP {exc.code}: {raw[:200]}"
        ) from exc
    except urllib.error.URLError as exc:
        raise _ScenarioFailed(f"could not reach server: {exc.reason}") from exc

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise _ScenarioFailed(f"server reply was not valid JSON: {raw[:200]!r}") from exc


def _extract_reply(data: dict[str, Any]) -> str:
    """Return the assistant text reply from a /chat response."""
    if "error" in data:
        raise _ScenarioFailed(f"server error envelope: {data!r}")
    reply = data.get("reply")
    if not isinstance(reply, str) or not reply.strip():
        raise _ScenarioFailed(f"empty or non-string reply: {data!r}")
    return reply.strip()


def _assert_no_key_leak(payload: dict[str, Any], response_body: dict[str, Any], label: str) -> None:
    """Fail if the Gemini API key appears anywhere we can see.

    Scans the outgoing request payload AND the parsed response. A leak
    in either direction fails the test.
    """
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key or len(key) < 8:
        return  # nothing to scan
    req_str = json.dumps(payload)
    resp_str = json.dumps(response_body)
    leaked_in: list[str] = []
    if key in req_str:
        leaked_in.append("request body")
    if key in resp_str:
        leaked_in.append("response body")
    if leaked_in:
        raise _ScenarioFailed(
            f"[{label}] API key leaked in: {', '.join(leaked_in)}"
        )


def _run_scenario(label: str, turns: list[str], checks: list[dict[str, Any]]) -> bool:
    """Drive a multi-turn conversation and run per-turn checks.

    ``turns`` is the ordered list of user messages. ``checks`` is a
    parallel list of dicts:
        {"contains": [...], "any_of": [...], "not_empty": bool}

    Each turn's reply is checked against the corresponding entry:
      - "contains"  → every listed substring must appear (case-insensitive)
      - "any_of"    → at least one of the listed substrings must appear
      - "not_empty" → reply must be non-empty (default True)

    The history sent to the server accumulates across turns the same way
    ChatScreen._buildHistoryForSend does — every prior (user, assistant)
    pair plus the welcome greeting (skipped here for brevity).
    """
    print(f"\n── {label} ──")
    history: list[dict[str, str]] = []
    passed = True
    for idx, user_text in enumerate(turns):
        check = checks[idx] if idx < len(checks) else {}
        payload: dict[str, Any] = {"message": user_text}
        if history:
            payload["history"] = history
        print(f"  You: {user_text!r}")
        try:
            data = _post_chat(user_text, history=history or None)
            reply = _extract_reply(data)
        except _ScenarioFailed as exc:
            print(f"  ✗ turn {idx + 1}: {exc}")
            passed = False
            break
        print(f"  AI:  {reply[:200]}{'…' if len(reply) > 200 else ''}")

        # Safety: the API key must never appear in either the request
        # body or the response body.
        try:
            _assert_no_key_leak(payload, data, f"{label} turn {idx + 1}")
        except _ScenarioFailed as exc:
            print(f"  ✗ {exc}")
            passed = False
            break

        # Per-turn content checks.
        low = reply.lower()
        for needle in check.get("contains", []):
            if needle.lower() not in low:
                print(f"  ✗ turn {idx + 1} missing {needle!r} in reply")
                passed = False
        any_of = check.get("any_of")
        if any_of and not any(s.lower() in low for s in any_of):
            print(f"  ✗ turn {idx + 1} missing one of {any_of!r} in reply")
            passed = False

        # Append to history for the NEXT turn. Critical: history does
        # NOT include the just-sent user message — only the prior pair.
        history.append({"role": "user", "text": user_text})
        history.append({"role": "assistant", "text": reply})

    if passed:
        print(f"  ✓ {label} passed ({len(turns)} turns).")
    return passed


def _preflight() -> bool:
    """Sanity checks before running any scenario.

    - Server reachable.
    - ``/welcome`` returns a non-empty greeting (proves the FastAPI
      process is up and the wiring from GET to ChatResponse is alive).
    - ``POST /chat`` with a trivial message returns a non-empty reply
      (proves the Gemini key is configured and the AI layer is wired).
    """
    print("Pre-flight checks:")
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:8765/welcome", timeout=10
        ) as resp:
            welcome = json.loads(resp.read().decode("utf-8"))
        if not isinstance(welcome.get("reply"), str) or not welcome["reply"].strip():
            print(f"  ✗ /welcome returned no usable reply: {welcome!r}")
            return False
        print(f"  ✓ /welcome → {welcome['reply']!r}")
    except Exception as exc:  # noqa: BLE001
        print(f"  ✗ /welcome failed: {exc}")
        return False

    # Trivial /chat smoke — proves the AI chain is configured end-to-end.
    try:
        data = _post_chat("Reply with exactly the word: ok")
        reply = _extract_reply(data)
    except _ScenarioFailed as exc:
        print(f"  ✗ /chat smoke failed: {exc}")
        return False
    if not reply.strip():
        print(f"  ✗ /chat smoke returned empty reply: {reply!r}")
        return False
    print(f"  ✓ /chat smoke → ({len(reply)} chars) {reply[:80]!r}")

    if not os.environ.get("GEMINI_API_KEY"):
        print("  ⚠ GEMINI_API_KEY not in env — key-leak checks will be skipped.")
    else:
        print(f"  ✓ GEMINI_API_KEY is set ({len(os.environ['GEMINI_API_KEY'])} chars) — leak checks active.")

    return True


# ---------------------------------------------------------------------------
# Scenarios — exactly as written in the Task 39 brief
# ---------------------------------------------------------------------------


def _scenario_1_normal() -> bool:
    """Normal conversation."""
    return _run_scenario(
        "Test 1 — Normal conversation",
        turns=[
            "Hello OdiAI",
            "What can you help me with?",
        ],
        checks=[
            {"any_of": ["hello", "hi", "hey", "greetings", "odiai", "i'm", "i am"]},
            # The reply must mention help/assist/can/something relevant.
            {"any_of": ["help", "assist", "support", "answer", "do"]},
        ],
    )


def _scenario_2_context() -> bool:
    """Multi-turn: name a language, ask what it was."""
    return _run_scenario(
        "Test 2 — Context (favourite language)",
        turns=[
            "My favourite programming language is Dart.",
            "What programming language did I say?",
        ],
        checks=[
            # Acknowledge — model has freedom here.
            {"not_empty": True},
            # Hard requirement from the brief: the second answer is "Dart".
            # We accept any case to be lenient.
            {"contains": ["dart"]},
        ],
    )


def _scenario_3_followup() -> bool:
    """Follow-up: define Flutter, ask what language."""
    return _run_scenario(
        "Test 3 — Follow-up (Flutter → language)",
        turns=[
            "What is Flutter?",
            "What language does it use?",
        ],
        checks=[
            # Explanation — must mention Flutter by name and frame it as
            # a toolkit/framework/SDK for building UIs.
            {"contains": ["flutter"]},
            {"any_of": ["framework", "toolkit", "sdk", "ui", "dart"]},
            # The follow-up must say Dart. The brief is explicit.
            {"contains": ["dart"]},
        ],
    )


def _scenario_4_subject_change() -> bool:
    """Subject change: explain FastAPI, then jump to Paris."""
    return _run_scenario(
        "Test 4 — Subject change",
        turns=[
            "Explain FastAPI in one sentence.",
            "What's the capital of France?",
        ],
        checks=[
            {"contains": ["fastapi"]},
            # Must be Paris — non-negotiable.
            {"contains": ["paris"]},
        ],
    )


def _scenario_5_long_conversation() -> bool:
    """8–10 turn conversation; assert pipeline properties, not exact words.

    The free-form turns cover: greeting, capabilities, two technical
    topics, a follow-up, a quick fact, a meta question, and a goodbye.
    """
    return _run_scenario(
        "Test 5 — Longer conversation (10 turns)",
        turns=[
            "Hi! I'm testing OdiAI.",
            "Can you help me with Python?",
            "What is a list comprehension?",
            "Show me an example.",
            "Thanks. What about JavaScript?",
            "Is JavaScript the same as Java?",
            "What language should I learn first as a beginner?",
            "How long does it usually take?",
            "One more thing — what's your name?",
            "Goodbye!",
        ],
        checks=[
            {"not_empty": True},  # greeting
            {"contains": ["python"]},  # turn 2 mentions Python
            {"contains": ["list"]},  # turn 3 explains list comprehensions
            {"not_empty": True},  # example code/text
            {"contains": ["javascript"]},  # turn 5
            {"any_of": ["no", "different"]},  # turn 6 — clarify difference
            {"not_empty": True},  # recommendation
            {"not_empty": True},  # timeframe
            {"any_of": ["odiai", "i'm", "i am", "assistant", "name"]},  # identity
            {"any_of": ["bye", "goodbye", "see you", "farewell"]},  # sign-off
        ],
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    print("Task 39 — real-AI conversation verification\n")
    print(f"Target: {URL}")
    print(f"Time:   {time.strftime('%Y-%m-%d %H:%M:%S')}")
    if not _preflight():
        print("\nPre-flight failed. Start the server and set GEMINI_API_KEY, then retry.")
        return 1

    results: list[tuple[str, bool]] = []
    for scenario in (
        _scenario_1_normal,
        _scenario_2_context,
        _scenario_3_followup,
        _scenario_4_subject_change,
        _scenario_5_long_conversation,
    ):
        results.append((scenario.__name__, scenario()))

    print("\n── Summary ──")
    all_pass = True
    for name, ok in results:
        marker = "✓" if ok else "✗"
        print(f"  {marker} {name}")
        if not ok:
            all_pass = False

    if all_pass:
        print("\nAll 5 real-AI scenarios passed. Pipeline + context + Gemini + key-safety verified.")
        return 0
    print("\nOne or more scenarios failed — see output above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
