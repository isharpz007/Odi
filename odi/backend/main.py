from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

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
class ChatRequest(BaseModel):
    message: str = Field(
        ...,
        min_length=1,
        max_length=2000,
        description="The text the user typed in the chat input.",
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


# IMPORTANT: Task 22/23 — POST /chat. Flutter will eventually send a
# ChatRequest and receive a ChatResponse. For now this is a no-AI stub:
# the server echoes the user's message back wrapped in a friendly phrase.
# Task 25 will replace the body with a real AI reply.
#
# IMPORTANT: Task 26 — failure-mode simulator. If the request includes
# `"simulate": "<code>"` in its body, we short-circuit and raise the
# documented error envelope instead of echoing. Supported codes:
#   validation_error     → HTTP 422
#   ai_unavailable       → HTTP 502
#   internal_error       → HTTP 500
#   malformed            → HTTP 200 with a junk body (broken JSON)
# The field is allowed as extra because `simulate` is not part of the
# ChatRequest schema; Pydantic accepts extra by default. Clients in
# production never send this.
@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
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
    return ChatResponse(reply=f"I received your message: {req.message}")