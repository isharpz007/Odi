🚀 Milestone 3 — Backend Integration

Now we're going to replace the mock chat response with a proper backend conversation system.

Milestone 3 tasks
#	Task	Status
21	Design the chat API	🔵 NEXT
22	Create POST /chat endpoint	⬜
23	Create request/response models	⬜
24	Connect Flutter to /chat	⬜
25	Send real messages to backend	⬜
26	Receive backend responses	⬜
27	Replace mock responses	⬜
28	Handle API errors	⬜
29	Test end-to-end chat	⬜
30	Complete Milestone 3	⬜
🟦 Task 21 — Design the Chat API

Before writing code, we're going to decide exactly how Flutter and Python communicate.

For example:

Flutter → FastAPI

{
  "message": "Hello OdiAI"
}

FastAPI → Flutter:

{
  "response": "Hello! How can I help you?"
}

The endpoint will eventually be:

POST /chat
Definition of Done

Decide and document:

 Endpoint: POST /chat
 Request format
 Response format
 Error format
 HTTP status codes

Don't write the endpoint yet.

This is another planning step — we're deliberately deciding the contract before coding it.

Once you've documented the API design, tell me Task 21 done and we'll build the endpoint.