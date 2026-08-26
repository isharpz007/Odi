🚀 Milestone 2 — Chat Interface

Now we're going to make OdiAI look and behave like an actual chatbot.

Our target:

┌──────────────────────────────────┐
│              OdiAI               │
├──────────────────────────────────┤
│                                  │
│  👋 Hello! I'm OdiAI.            │
│                                  │
│                  Hello OdiAI 👤  │
│                                  │
│  How can I help you today?       │
│                                  │
│                                  │
├──────────────────────────────────┤
│  Type a message...          🎤   │
└──────────────────────────────────┘
Milestone 2 tasks
#	Task	Status
11	Create chat screen	🔵 NEXT
12	Create message bubble	⬜
13	Create message input	⬜
14	Create send button	⬜
15	Display user messages	⬜
16	Display AI messages	⬜
17	Add scrolling conversation	⬜
18	Add loading state	⬜
19	Add basic chat UI testing	⬜
20	Complete Milestone 2	⬜
🎯 Task 11 — Create Chat Screen

Create this task in your board:

Task name:

Create Chat Screen

Definition of Done:

 OdiAI has a dedicated chat screen
 App bar/header says OdiAI
 Chat area exists
 Message input area exists
 Screen works on your selected platform
 No backend/AI functionality is required yet

Important: We're focusing on the UI only.

Don't connect the AI.

Don't add voice.

Don't create the message API.

We're going to build the interface first, then make it intelligent.

Once you've created and completed Task 11, tell me:

Task 11 done.


Task 20 — Complete Milestone 2

This is your Milestone 2 checkpoint.

Confirm the chat interface is complete
┌──────────────────────────────┐
│            OdiAI             │
├──────────────────────────────┤
│                              │
│  AI message                  │
│                              │
│              User message    │
│                              │
│  AI message                  │
│                              │
│              User message    │
│                              │
│        ↕ Scrollable          │
│                              │
├──────────────────────────────┤
│ Message...              ◯    │
└──────────────────────────────┘

You now have:

✅ Figma-inspired interface
✅ Message bubbles
✅ Message input
✅ Send button
✅ User messages
✅ Mock AI messages
✅ Scrolling
✅ Loading state
✅ UI testing
One final thing

Commit the milestone to Git:

git add .
git commit -m "milestone: complete chat interface"
git push

Once that's pushed, mark:

Task 20 done — Milestone 2 complete


Task 20 — Complete Milestone 2

This is another checkpoint.

Your chat interface should now have:
                 OdiAI
                  │
        ┌─────────▼─────────┐
        │                   │
        │   AI messages     │
        │                   │
        │        User       │
        │      messages     │
        │                   │
        │   OdiAI thinking  │
        │                   │
        ├───────────────────┤
        │ Message...    ➤   │
        └───────────────────┘
Definition of Done

Confirm:

 Figma design recreated
 Message bubbles
 Message input
 Send button
 User messages
 AI mock responses
 Scrolling
 Loading state
 UI testing
Then commit your work

From your project directory:

git status

Then:

git add .
git commit -m "milestone: complete chat interface"
git push

Once you've done that:

Task 20 done — Milestone 2 complete

Then we'll start Milestone 3 — Backend Integration.

That's where things get more interesting:

CURRENT
Flutter
   ↓
Mock AI

becomes:

Flutter
   ↓
Python + FastAPI
   ↓
Chat API
   ↓
Response
   ↓
Flutter

Still no real AI yet. We'll connect the backend properly first.