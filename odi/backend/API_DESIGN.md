# OdiAI Chat API — Design

> **Status:** Draft (Task 21). Implementation arrives in Task 22.
> **Owner:** Backend (FastAPI) + Flutter client.
> **Goal:** Lock the wire format between Flutter and FastAPI **before** any
> code is written, so the two sides can be built in parallel.

---

## 1. Architecture

```
┌──────────────┐
│    Flutter   │
│   OdiAI UI   │  (mobile / desktop / web)
└──────┬───────┘
       │
       │  HTTP POST /chat
       │  Content-Type: application/json
       │  Body: { "message": "Hello OdiAI" }
       ▼
┌──────────────┐
│   FastAPI    │
│   Python     │  (this repo, /backend)
└──────┬───────┘
       │
       │  HTTP 200 OK
       │  Content-Type: application/json
       │  Body: { "reply": "Hello! How can I help you?" }
       ▼
┌──────────────┐
│    Flutter   │
│ AI response  │  rendered as a chat bubble
└──────────────┘
```

The transport is plain HTTP + JSON. No streaming, no websockets, no
server-sent events yet — those are deliberate out-of-scope decisions for
later milestones. Every turn is one round-trip.

---

## 2. Endpoints

| Path | Method | Purpose |
| --- | --- | --- |
| `/welcome` | `GET` | Initial greeting shown when the conversation is empty. Returns `{"reply": "..."}`. |
| `/chat` | `POST` | Send a message, receive a single assistant reply (JSON). |
| `/chat/stream` | `POST` | Send a message, receive the assistant reply as a stream of text deltas (text/plain). |

All endpoints accept and return UTF-8 JSON for the request/response shape
described below. Auth is **None** for now; later tasks will add a bearer
token in `Authorization`. CORS is configured as `allow_origins=["*"]` in
`backend/main.py`.

### Why POST and not GET

- The request carries a user-supplied message body.
- GET would force the message into the URL, which has length limits, leaks
  content into logs and analytics, and is not cache-friendly.
- POST is the conventional choice for "send something, get a generated
  reply."

---

## 3. Request — success

```http
POST /chat HTTP/1.1
Host: 127.0.0.1:8000
Content-Type: application/json
Accept: application/json

{
  "message": "Hello OdiAI"
}
```

### Request schema

| Field | Type | Required | Constraints | Description |
| --- | --- | --- | --- | --- |
| `message` | `string` | **yes** | 1–2000 chars, trimmed, non-empty after trim | The text the user typed in the chat input. |
| `history` | `array<HistoryTurn>` | no | Empty or omitted = single-turn (no context) | Prior conversation turns so the model can answer follow-ups. |
| `simulate` | `string` | no | One of `validation_error`, `ai_unavailable`, `internal_error`, `malformed`, `slow[:N]` | Test-only failure-mode short-circuit. Production clients never set this. |

#### `HistoryTurn` shape

| Field | Type | Required | Constraints | Description |
| --- | --- | --- | --- | --- |
| `role` | `string` enum | **yes** | `"user"` or `"assistant"` | Who produced the turn. |
| `text` | `string` | **yes** | 1–2000 chars, non-empty | The text of the turn. |

Example multi-turn request:

```json
{
  "message": "What's my name?",
  "history": [
    { "role": "user", "text": "My name is Odi." },
    { "role": "assistant", "text": "Nice to meet you, Odi." }
  ]
}
```

The server **must** reject any request that fails validation with HTTP 422
(FastAPI's default for `RequestValidationError`).

### Examples

```json
{ "message": "Hello OdiAI" }
```

```json
{ "message": "What can you do?" }
```

```json
{ "message": "Line 1\nLine 2\nLine 3" }
```

The server does not need to know whether the message came from a single
tap or a multi-line paste — it just sees the string.

---

## 4. Response — success

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "reply": "Hello! How can I help you?"
}
```

### Response schema

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `reply` | `string` | **yes** | The assistant's text reply. Always non-empty. |

### Examples

```json
{ "reply": "Hello! How can I help you today?" }
```

```json
{ "reply": "That's a great question — here's what I'd suggest…" }
```

```json
{ "reply": "Got it — tell me more and I'll dig in." }
```

### Why `reply` and not `message`

- The Flutter side already uses a `ChatMessage` model where `text` holds the
  bubble content and `isUser` flags the author. The wire format only carries
  the **content** of the assistant message, so a single `reply` field is
  unambiguous.
- Avoids reusing the word "message" for both halves of the conversation.

---

## 5. Errors

The backend uses standard HTTP status codes plus a structured JSON body so
the Flutter client can display a useful message.

### 5.1 Validation error — HTTP 422

Triggered when the request body is missing `message`, has the wrong type,
or is empty / whitespace-only.

```http
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json

{
  "error": "validation_error",
  "detail": "message must be a non-empty string"
}
```

### 5.2 Bad gateway / model failure — HTTP 502

Triggered when **every** configured provider in the AI chain fails to
produce a reply (timeout, upstream error, quota exceeded, missing API
key, etc.). Flutter should show this as a transient error and offer a
retry.

```http
HTTP/1.1 502 Bad Gateway
Content-Type: application/json

{
  "error": "ai_unavailable",
  "detail": "Upstream model did not respond"
}
```

Internally the server walks a configured chain of providers (see §7
"Provider configuration"). On **transient** failures (HTTP 429, 5xx,
network/timeout) the next provider is tried automatically. The Flutter
client cannot tell which provider in the chain actually answered.

On **permanent** failures (HTTP 400, 401, 403, 404, safety block, empty
response) the chain stops immediately and surfaces the error — switching
providers won't fix an auth failure.

### 5.3 Internal server error — HTTP 500

Anything else that goes wrong on the server side.

```http
HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{
  "error": "internal_error",
  "detail": "Unexpected server error"
}
```

### Error schema

| Field | Type | Required | Description |
| --- | --- | --- | --- |
| `error` | `string` (enum) | **yes** | One of `validation_error`, `ai_unavailable`, `internal_error`. Stable across versions — Flutter can branch on this value. |
| `detail` | `string` | **yes** | Human-readable explanation. Safe to show in the UI. |

### Status code summary

| Status | When | `error` value |
| --- | --- | --- |
| 200 | Successful reply | (no `error` field) |
| 422 | Bad request body | `validation_error` |
| 502 | AI upstream failed | `ai_unavailable` |
| 500 | Anything else | `internal_error` |

---

## 6. Flutter → FastAPI flow

### 6.1 On send

```
ChatInput (Flutter)
   │
   │ user taps Send
   ▼
ChatScreen._onUserSend(text)
   │
   │ 1) Append user bubble to local state, clear input
   │ 2) Show LoadingBubble, set _isLoading = true
   │ 3) Call ApiClient.sendMessage(text)
   │        │
   │        │  POST http://<host>:<port>/chat
   │        │  Content-Type: application/json
   │        │  { "message": text }
   │        ▼
   │     FastAPI /chat
   │        │
   │        │  validates body
   │        │  generates reply (mock in Task 22)
   │        │
   │        │  200 OK  { "reply": "..." }
   │        ▼
   │     ApiClient returns the reply string
   │
   │ 4) Hide LoadingBubble, append AI bubble
   ▼
ChatScreen rebuilds
```

### 6.2 On error

```
ApiClient.sendMessage throws ApiException
   │
   │  - statusCode
   │  - errorCode  ("validation_error", "ai_unavailable", "internal_error")
   │  - detail
   ▼
ChatScreen shows a transient error bubble:
   "Sorry — <detail>. Please try again."
   │
   │ does NOT clear the user's input — the message can be retried
   ▼
User taps Send again
```

The Flutter side keeps `_isLoading = false` after an error so the input
stays editable. The user message stays in the chat thread so the user
can see what they tried to send.

---

## 6. Streaming endpoint (`/chat/stream`)

`POST /chat/stream` accepts the same `ChatRequest` body as `/chat` and
returns the assistant reply as it is generated, so the UI can render
tokens as they arrive instead of waiting for the full reply.

### Wire format

- `Content-Type: text/plain; charset=utf-8`
- Each AI text delta is yielded as-is (raw UTF-8, no framing).
- A single newline (`\n`) marks the end of a successful stream.
- A line beginning with `ERROR: ` (one space after the colon) marks a
  mid-stream error; the rest of the line is the human-readable detail.

```
POST /chat/stream HTTP/1.1
Content-Type: application/json

{"message": "Tell me a story"}

─── response body ───
Sure,
 once upon a time...
ERROR: Upstream model did not respond
```

### Client behavior

- Concatenate text deltas into the AI bubble (no separators; the deltas
  are already word-bounded).
- On the empty-line end sentinel, finalize the bubble.
- On an `ERROR:` line, render an error bubble over the partial text
  (the current Flutter behavior discards partial text on error).

### Streaming fallback rule

The chain walks providers in order. If a provider fails **before**
yielding any token, the next provider is tried silently — the client
never sees the failure. Once a provider yields its first token, the
chain locks to that provider; subsequent errors propagate as an
`ERROR:` line. This means a partial reply on screen plus an error bubble
over it, never a spliced-together multi-provider reply.

---

## 7. Base URL configuration

| Environment | Base URL |
| --- | --- |
| Flutter desktop / web (local dev) | `http://127.0.0.1:8000` |
| Flutter Android emulator (local dev) | `http://10.0.2.2:8000` |
| Production | `https://api.odiai.example.com` |

These are picked by an `ApiClient` factory at startup; the rest of the app
only depends on `ApiClient.sendMessage(text) → Future<String>`. The host
details never leak into UI code.

---

## 7. Provider configuration (server-side)

The server picks the AI provider from a configured chain. The Flutter
client does not select providers — the request body has no `model` or
`provider` field.

### Environment variable

```
ODIAI_MODEL_CHAIN=gemini:gemini-3.5-flash-lite,openai:gpt-4o-mini,anthropic:claude-haiku-4-5-20251001
```

- Comma-separated `provider_kind:model_id` entries, evaluated left to
  right.
- Default if unset: `gemini:gemini-3.5-flash-lite` (single-provider).
- Providers whose corresponding API key env var is missing (`GEMINI_API_KEY`,
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`) are skipped silently with an
  INFO log line at first request.
- Malformed entries (no colon, empty on either side) are dropped with a
  WARNING log.

### Picking models

- **Gemini** — `gemini-3.5-flash-lite` (cheap/fast), or any other model id
  accepted by the `google-genai` SDK.
- **OpenAI** — `gpt-4o-mini` (cheap), `gpt-4o` (stronger), or any other
  model id accepted by the `openai` SDK Chat Completions endpoint.
- **Anthropic** — `claude-haiku-4-5-20251001` (cheap), `claude-sonnet-5`
  (stronger), or any other model id accepted by the `anthropic` SDK
  Messages endpoint.

You can mix and match any subset. If only one provider's key is
configured, the chain silently degrades to a single-provider setup;
the client never sees the difference.

### Behavior

- **Transient errors** (HTTP 429, 5xx, network/timeout): try the next
  provider in the chain automatically. The Flutter client cannot tell
  which provider answered.
- **Permanent errors** (HTTP 400, 401, 403, 404, safety block, empty
  response): raise immediately, no fallback. The response body is the
  `ai_unavailable` envelope as for any other failure.
- **All providers fail**: 502 `ai_unavailable` with the last retryable
  error's detail as `detail`.
- **No providers configured**: 502 `ai_unavailable` with detail "No AI
  providers configured…".

---

## 8. Out of scope (deliberately deferred)

These are **not** part of the current milestone:

- Conversation history persistence (the server is stateless; Flutter owns
  the thread and sends it back in `history`).
- Authentication / rate limiting / per-user quotas.
- File uploads, image inputs, voice.
- Per-request provider selection (the request body has no `model` field;
  selection happens server-side via `ODIAI_MODEL_CHAIN`).
- Token-usage telemetry (usage differs per provider; deferred).

---

## 9. Versioning

The endpoint is unversioned at `/chat` for now. When we ship a breaking
change (e.g. server-side conversation memory, or streaming), we will
introduce `/v2/chat` and keep `/chat` serving the old contract until the
client migrates.
