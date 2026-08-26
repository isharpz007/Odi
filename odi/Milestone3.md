🟦 Task 21 — Design the Chat API

Before we write code, we're going to decide exactly how Flutter and FastAPI communicate.

Request

Flutter will eventually send:

{
  "message": "Hello OdiAI"
}

to:

POST /chat
Response

FastAPI will return:

{
  "reply": "Hello! How can I help you?"
}

So the architecture becomes:

┌──────────────┐
│    Flutter   │
│   OdiAI UI   │
└──────┬───────┘
       │
       │ POST /chat
       │ { message }
       ▼
┌──────────────┐
│   FastAPI    │
│   Python     │
└──────┬───────┘
       │
       │ response
       ▼
┌──────────────┐
│    Flutter   │
│ AI response  │
└──────────────┘
Definition of Done
 /chat endpoint defined
 Request format defined
 Response format defined
 Error format defined
 Flutter → FastAPI flow documented

No AI API yet.

We're deliberately designing the interface first. Once Task 21 is complete, Task 22 will be implementing it in Python.