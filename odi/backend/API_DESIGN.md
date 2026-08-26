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

## 2. Endpoint

| Field | Value |
| --- | --- |
| Path | `/chat` |
| Method | `POST` |
| Content-Type (request) | `application/json` |
| Content-Type (response) | `application/json` |
| Auth | **None** (Task 21). Later: bearer token in `Authorization` header. |
| CORS | `allow_origins=["*"]` (already configured in `backend/main.py`). |

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

Triggered when the AI layer fails to produce a reply (timeout, upstream
error, quota exceeded, etc.). Flutter should show this as a transient
error and offer a retry.

```http
HTTP/1.1 502 Bad Gateway
Content-Type: application/json

{
  "error": "ai_unavailable",
  "detail": "Upstream model did not respond"
}
```

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

## 8. Out of scope (deliberately deferred)

These are **not** part of Task 21 — each becomes its own task later:

- Streaming / chunked responses (server-sent events or websockets).
- Conversation history. `/chat` is stateless; Flutter owns the thread.
- Authentication / rate limiting / per-user quotas.
- File uploads, image inputs, voice.
- Multi-model selection (the request doesn't carry a `model` field).

---

## 9. Versioning

The endpoint is unversioned at `/chat` for now. When we ship a breaking
change (e.g. server-side conversation memory, or streaming), we will
introduce `/v2/chat` and keep `/chat` serving the old contract until the
client migrates.
