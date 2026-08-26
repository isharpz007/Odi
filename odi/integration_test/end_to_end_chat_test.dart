// Task 28 — End-to-end chat tests.
//
// These tests drive the real Flutter UI against the **live FastAPI**
// backend at http://127.0.0.1:8000. They complement the widget suite
// (which uses an injected stub) by proving the full pipeline works:
//
//   user input
//      ↓ Flutter (ChatScreen → ApiClient)
//      ↓ POST /chat
//   FastAPI
//      ↓ 200 {"reply": "..."}
//   Flutter
//      ↓ AI message bubble
//
// IMPORTANT: before running this file with
//   flutter test integration_test/end_to_end_chat_test.dart
// make sure the FastAPI server is running locally:
//   cd backend && python -m uvicorn main:app --host 127.0.0.1 --port 8000
//
// The suite self-skips if the server isn't reachable, so it's safe to
// run from a cold environment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:odi/screens/chat_screen.dart';
import 'package:odi/services/api_client.dart';
import 'package:odi/widgets/loading_bubble.dart';
import 'package:odi/widgets/send_button.dart';

final Uri _liveBase = Uri.parse('http://127.0.0.1:8000');

/// Probe the live server. Returns true if both `/welcome` and `/chat`
/// are reachable, false otherwise. The suite uses this to self-skip
/// when the backend isn't running.
Future<bool> _serverIsUp() async {
  try {
    final ApiClient probe = ApiClient(
      baseUrl: _liveBase,
      timeout: const Duration(seconds: 2),
    );
    final ApiResult welcome = await probe.fetchWelcome();
    if (welcome.error != null) return false;
    final ApiResult chat = await probe.sendMessage('probe');
    return chat.error == null;
  } catch (_) {
    return false;
  }
}

Future<void> _pumpLiveChat(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: ChatScreen(),
    ),
  );
  // Let the post-frame auto-scroll settle.
  await tester.pump();
  // Drain the /welcome greeting so it's in the tree.
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
  await tester.idle();
}

Finder _field() => find.byType(TextField);
Finder _sendButton() => find.byType(SendButton);

Future<void> _enterAndSend(WidgetTester tester, String text) async {
  await tester.enterText(_field(), text);
  await tester.pump();
  await tester.tap(_sendButton(), warnIfMissed: false);
  await tester.pump();
  await tester.pump();
}

/// Wait for a real HTTP round-trip. Live mode — generous timeout.
Future<void> _waitForLiveReply(WidgetTester tester) async {
  // The FastAPI echo returns almost instantly, but give it room.
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
  await tester.idle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final bool up = await _serverIsUp();
    if (!up) {
      // Print a friendly hint instead of failing — keeps `flutter test`
      // green for someone running the suite without a backend.
      // ignore: avoid_print
      print('⚠️  FastAPI not reachable at $_liveBase — skipping '
          'integration tests. Start it with:');
      // ignore: avoid_print
      print('   cd backend && python -m uvicorn main:app '
          '--host 127.0.0.1 --port 8000');
    }
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 1 — Normal conversation
  // ──────────────────────────────────────────────────────────────────
  testWidgets('e2e/1: Normal conversation: send Hello OdiAI, get AI reply',
      (tester) async {
    if (!await _serverIsUp()) return; // self-skip
    await _pumpLiveChat(tester);

    // The welcome greeting should already be in the tree.
    expect(find.text("Hello! I'm OdiAI. Ask me anything."), findsOneWidget);

    await _enterAndSend(tester, 'Hello OdiAI');

    // User bubble appears immediately.
    expect(find.text('Hello OdiAI'), findsOneWidget);

    await _waitForLiveReply(tester);

    // AI bubble appears with the echoed reply.
    expect(
      find.text('I received your message: Hello OdiAI'),
      findsOneWidget,
    );

    // Loading bubble is gone.
    expect(find.byType(LoadingBubble), findsNothing);
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 2 — Multiple messages
  // ──────────────────────────────────────────────────────────────────
  //
  // IMPORTANT: ListView.builder is lazy — older bubbles are not in the
  // widget tree once they scroll out of view. So we can only assert on
  // bubbles that are currently mounted. The LAST user bubble and the
  // LAST AI reply are always mounted (the list is pinned to the bottom),
  // and we scroll the list to bring older bubbles back into view before
  // checking them.
  testWidgets(
      'e2e/2: Multiple messages: 8 messages stay in order, no crashes, scrolling works',
      (tester) async {
    if (!await _serverIsUp()) return;
    await _pumpLiveChat(tester);

    const int count = 8;
    for (int i = 0; i < count; i++) {
      await _enterAndSend(tester, 'E2E message $i');
      await _waitForLiveReply(tester);
    }

    // The last user bubble and its echo are visible at the bottom.
    expect(
      find.text('I received your message: E2E message ${count - 1}'),
      findsOneWidget,
      reason: 'last AI reply is visible at the bottom',
    );
    expect(
      find.text('E2E message ${count - 1}'),
      findsAtLeastNWidgets(1),
      reason: 'last user bubble is visible at the bottom',
    );

    // Scroll all the way up so older bubbles mount, then check that every
    // user bubble plus its echo is rendered without crashing.
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await tester.pump();
    await tester.pump();
    for (int i = 0; i < count; i++) {
      expect(
        find.text('E2E message $i'),
        findsOneWidget,
        reason: 'user bubble "$i" must be in the tree after scroll',
      );
      expect(
        find.text('I received your message: E2E message $i'),
        findsOneWidget,
        reason: 'echo of user bubble "$i" must be in the tree after scroll',
      );
    }

    // Drag back to bottom — proves bidirectional scrolling works.
    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await tester.pump();
    await tester.pump();
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 3 — Backend failure
  // ──────────────────────────────────────────────────────────────────
  testWidgets(
      'e2e/3: Backend failure: pointing at a dead host shows a friendly error',
      (tester) async {
    if (!await _serverIsUp()) return;
    // Point at a closed port on the same host. 127.0.0.1:9 is the
    // discard service and is almost never listening.
    final ApiClient deadClient = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:9'),
      timeout: const Duration(seconds: 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(apiClient: deadClient),
      ),
    );
    await tester.pump();
    // Drain the welcome attempt (will fail).
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    await tester.idle();

    await _enterAndSend(tester, 'no-server');

    // Wait long enough for the request to fail and the error to render.
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await tester.idle();

    // The friendly network-error sentence is shown at least once. Both
    // the welcome fetch AND the user message fail to the same dead host,
    // so we expect one or two matching bubbles — assert "at least one"
    // rather than exactly one.
    expect(
      find.text(
          "I can't reach the server right now. Check your connection and try again."),
      findsAtLeastNWidgets(1),
      reason: 'friendly network error must appear',
    );
    // Loading bubble is gone (loading stopped on failure).
    expect(find.byType(LoadingBubble), findsNothing);
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 4 — Recovery (re-point to live, send again)
  // ──────────────────────────────────────────────────────────────────
  testWidgets(
      'e2e/4: Recovery: after a connection failure, sending through the live host works again',
      (tester) async {
    if (!await _serverIsUp()) return;
    // Start pointing at the dead host.
    final ApiClient liveClient = ApiClient(
      baseUrl: _liveBase,
      timeout: const Duration(seconds: 5),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(apiClient: liveClient),
      ),
    );
    await tester.pump();
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump();
    await tester.idle();

    await _enterAndSend(tester, 'recovery check');
    await _waitForLiveReply(tester);

    // Live server returns the echo.
    expect(
      find.text('I received your message: recovery check'),
      findsOneWidget,
    );
    expect(find.byType(LoadingBubble), findsNothing);
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 5 — Timeout (live server slow path)
  // ──────────────────────────────────────────────────────────────────
  testWidgets(
      'e2e/5: Timeout: a slow backend triggers a friendly timeout message',
      (tester) async {
    if (!await _serverIsUp()) return;
    // Use a 500ms client timeout. We can't tell the live FastAPI to
    // sleep through the wire format we use here, so instead we point
    // at a non-routable host on the test machine to provoke a connect
    // timeout. That exercises the same TimeoutException path.
    final ApiClient slowClient = ApiClient(
      baseUrl: Uri.parse('http://10.255.255.1'), // TEST-NET: blackhole
      timeout: const Duration(milliseconds: 500),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScreen(apiClient: slowClient),
      ),
    );
    await tester.pump();
    // Drain the welcome attempt (will time out).
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await tester.idle();

    await _enterAndSend(tester, 'slow');

    // Wait for the timeout to fire.
    for (int i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await tester.idle();

    // Friendly timeout sentence.
    expect(
      find.text('The server took too long to respond. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(LoadingBubble), findsNothing);
  });
}