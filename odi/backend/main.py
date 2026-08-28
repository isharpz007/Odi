from dotenv import load_dotenv
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field, field_validator
from typing import Literal

# IMPORTANT: Task 33/34 — load environment variables from `backend/.env`
# *before* any module that reads them (notably `ai.py`) is imported.
# `load_dotenv` is a no-op when the file is absent, so production
# deployments that inject env vars through the host environment keep
# working without modification.
load_dotenv()

import ai  # noqa: E402,F401  — must come after load_dotenv() so the env var is set; F401 because ai is used at runtime inside chat()

app = FastAPI()


# IMPORTANT: Task 26 — uniform error envelope. FastAPI's default for
# RequestValidationError is a raw list (`{"detail": [...]}`); for any
# other uncaught exception it returns a plain string. We override both
# so every error response matches the contract documented in
# `backend/API_DESIGN.md` §5: `{ "error": "<stable_code>", "detail": "..." }`.
# The Flutter ApiClient parses that exact shape.
@app.exception_handler(RequestValidationError)
async def _validation_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    # FastAPI requires both `request` and `exc` in the signature even
    # though we only read `exc`. Reference `_request` so static analysers
    # don't flag it as unused.
    del _request
    # Combine Pydantic's per-field error list into a single human
    # readable sentence so Flutter can show it as-is.
    parts = []
    for err in exc.errors():
        loc = ".".join(str(p) for p in err.get("loc", []))
        msg = err.get("msg", "invalid value")
        parts.append(f"{loc}: {msg}" if loc else msg)
    detail = "; ".join(parts) if parts else "Request body is invalid."
    return JSONResponse(
        status_code=422,
        content={"error": "validation_error", "detail": detail},
    )


@app.exception_handler(Exception)
async def _unhandled_handler(_request: Request, _exc: Exception) -> JSONResponse:
    # FastAPI requires both `request` and `exc` in the signature even
    # though this is a blanket handler. Reference both so static
    # analysers don't flag them as unused.
    _ = _request
    _ = _exc
    # Last-resort safety net so a stray bug never leaks a stack trace
    # to the client.
    return JSONResponse(
        status_code=500,
        content={"error": "internal_error", "detail": "Unexpected server error."},
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# IMPORTANT: Task 23 — typed request/response models. These define the
# wire contract between Flutter and FastAPI. Field constraints here are
# what the Flutter client relies on:
#   - message: required, 1..2000 chars, non-empty after trim
#   - reply:   required, non-empty string
# Anything that fails these constraints is rejected with HTTP 422 before
# any AI work happens, so the AI layer never sees garbage input.
#
# IMPORTANT: Task 38 — `HistoryTurn` is declared *before* `ChatRequest`
# so the `history: list[HistoryTurn]` field is a concrete type reference
# rather than a string forward-reference. That keeps both Pylance (no
# unused `Literal` import) and Pydantic happy without `model_rebuild`.
class HistoryTurn(BaseModel):
    """A single prior turn in the current conversation.

    Used by ``ChatRequest.history``. We constrain the wire shape with a
    Pydantic model so a malformed payload produces a clean 422 instead
    of crashing the AI service layer.
    """

    role: Literal["user", "assistant"] = Field(
        ...,
        description="Who produced this turn. 'assistant' is the AI's reply.",
    )
    text: str = Field(
        ...,
        min_length=1,
        max_length=2000,
        description="The text of the turn.",
    )


class ChatRequest(BaseModel):
    message: str = Field(
        ...,
        min_length=1,
        max_length=2000,
        description="The text the user typed in the chat input.",
    )

    # IMPORTANT: Task 38 — conversation context for the current chat.
    # Optional list of prior turns as ``{"role": "user" | "assistant",
    # "text": "..."}`` dicts. Empty / omitted keeps single-turn behaviour
    # so any existing client continues to work without changes.
    history: list[HistoryTurn] | None = Field(
        default=None,
        description=(
            "Optional list of prior conversation turns for the current "
            "chat. Each turn is {role: 'user'|'assistant', text: str}. "
            "When omitted the request is single-turn (no context)."
        ),
    )

    # IMPORTANT: Task 26 — failure-mode simulator used by integration
    # tests. Production clients never set this field; when it is set
    # to one of the documented codes, the endpoint short-circuits to
    # the corresponding error envelope instead of echoing.
    simulate: str | None = Field(
        default=None,
        description="Optional failure-mode code for testing: validation_error, ai_unavailable, internal_error, malformed.",
    )

    @field_validator("message")
    @classmethod
    def _message_not_blank(cls, value: str) -> str:
        # IMPORTANT: reject whitespace-only messages even though min_length=1
        # would technically allow "   ". We treat the field as "the user's
        # actual message", which is meaningless if it's only whitespace.
        stripped = value.strip()
        if not stripped:
            raise ValueError("message must not be blank")
        return stripped


class ChatResponse(BaseModel):
    reply: str = Field(
        ...,
        min_length=1,
        description="The assistant's text reply.",
    )


# IMPORTANT: Task 25 — the Flutter chat screen asks for a starter
# greeting instead of seeding a hardcoded bubble. The greeting still
# lives on the backend (no AI yet, just a friendly static string) so
# the architecture is "every user-visible line of assistant text comes
# from FastAPI". When Milestone 4 swaps in the real AI, this endpoint
# can be promoted to a real generation call.
class WelcomeResponse(BaseModel):
    reply: str = Field(
        ...,
        min_length=1,
        description="A short greeting shown when the conversation is empty.",
    )


@app.get("/welcome", response_model=WelcomeResponse)
def welcome() -> WelcomeResponse:
    return WelcomeResponse(reply="Hello! I'm OdiAI. Ask me anything.")


@app.get("/")
def root():
    return {"message": "OdiAI backend is running"}


@app.get("/hello")
def hello():
    return {
        "message": " ".join(["kanye west is the goat!"] * 4),
    }


# IMPORTANT: Task 22/23 — POST /chat. Flutter sends a ChatRequest and
# receives a ChatResponse. As of Task 34 the reply comes from Gemini via
# the service layer in `ai.py`; the previous echo response has been
# removed.
#
# IMPORTANT: Task 26 — failure-mode simulator. If the request includes
# `"simulate": "<code>"` in its body, we short-circuit and raise the
# documented error envelope instead of hitting Gemini. Supported codes:
#   validation_error     → HTTP 422
#   ai_unavailable       → HTTP 502
#   internal_error       → HTTP 500
#   malformed            → HTTP 200 with a junk body (broken JSON)
#   slow[:seconds]       → sleeps for N seconds (default 30) before
#                          returning a real reply
# The field is allowed as extra because `simulate` is not part of the
# ChatRequest schema; Pydantic accepts extra by default. Clients in
# production never send this.
@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    sim = req.simulate
    if sim:
        # IMPORTANT: return JSONResponse directly (instead of raising
        # HTTPException) so the response body is exactly
        # `{ "error": "<code>", "detail": "<msg>" }` — matching the
        # contract the Flutter ApiClient parses. HTTPException would
        # wrap that under its own `detail` key.
        if sim == "validation_error":
            return JSONResponse(
                status_code=422,
                content={"error": "validation_error", "detail": "Message is invalid."},
            )
        if sim == "ai_unavailable":
            return JSONResponse(
                status_code=502,
                content={"error": "ai_unavailable", "detail": "Upstream model did not respond."},
            )
        if sim == "internal_error":
            return JSONResponse(
                status_code=500,
                content={"error": "internal_error", "detail": "Unexpected server error."},
            )
        # For "malformed" we deliberately return 200 with junk so the
        # client exercises its JSON parser path.
        if sim == "malformed":
            return JSONResponse(
                status_code=200,
                content="this-is-not-json-{{{",
                media_type="text/plain",
            )
        # IMPORTANT: Task 27 — `slow` simulator. Sleeps for
        # `slow_seconds` (default 30s) so the client's timeout fires.
        # An optional numeric suffix is allowed: `simulate: "slow:5"`.
        # Used by the Flutter timeout tests.
        if sim == "slow" or sim.startswith("slow:"):
            import time as _time
            seconds = 30
            if sim.startswith("slow:"):
                try:
                    seconds = int(sim.split(":", 1)[1])
                except (ValueError, IndexError):
                    pass
            _time.sleep(seconds)
            return ChatResponse(reply="slow-but-eventually")

    # IMPORTANT: Task 34 — the real path. Hand the user's message to the
    # AI service layer and return whatever it produces. We catch the
    # service's typed exception and translate it into the documented
    # 502 envelope so the Flutter client surfaces a friendly error.
    #
    # IMPORTANT: Task 38 — pipe the optional conversation history through
    # so Gemini sees prior turns and can answer follow-ups. We translate
    # Pydantic ``HistoryTurn`` objects to plain dicts because the AI
    # service layer accepts an iterable of ``{"role", "text"}`` dicts
    # (the wire format the Flutter client also produces).
    history_dicts = (
        None if req.history is None
        else [{"role": t.role, "text": t.text} for t in req.history]
    )
    try:
        reply_text = await ai.generate_reply(req.message, history=history_dicts)
    except ai.AIServiceError as exc:
        return JSONResponse(
            status_code=502,
            content={"error": "ai_unavailable", "detail": exc.detail},
        )
    return ChatResponse(reply=reply_text)


# IMPORTANT: Task 38½ — streaming variant of /chat. Returns
# text/plain chunks as Gemini produces them so the Flutter UI can
# render tokens as they arrive (typewriter effect, perceived latency
# drops from "full reply" to "first token", usually ~600 ms).
#
# Wire format: each chunk is a UTF-8 text delta terminated by a
# newline. A single empty line (`\n\n`) at the end signals completion.
# Errors mid-stream are encoded as `ERROR: <detail>\n` so the Flutter
# client can render them as an error bubble.
#
# The /chat endpoint above still works for any client that wants the
# old JSON shape — nothing regresses. Flutter opts into streaming by
# POSTing here instead.
@app.post("/chat/stream")
async def chat_stream(req: ChatRequest):
    history_dicts = (
        None if req.history is None
        else [{"role": t.role, "text": t.text} for t in req.history]
    )

    async def event_generator():
        try:
            async for delta in ai.stream_reply(req.message, history=history_dicts):
                # Each delta is a chunk of text. Yield it as-is; the
                # client concatenates. We don't add separators because
                # Gemini's deltas are already word-bounded.
                yield delta
            # Sentinel: empty line means "stream finished cleanly".
            yield "\n"
        except ai.AIServiceError as exc:
            # Errors mid-stream are encoded so the client can show
            # them as an error bubble instead of a partial AI reply.
            yield f"ERROR: {exc.detail}\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/plain; charset=utf-8",
    )