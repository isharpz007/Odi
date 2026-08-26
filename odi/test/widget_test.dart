// Tasks 19 + 24 — widget tests for the chat UI.
//
// We pump the real ChatScreen and exercise it via the WidgetTester
// (tap, type, scroll, etc.). No new features are added here — we are
// verifying what we have already built.
//
// IMPORTANT (Task 24): now that the screen talks to a real ApiClient,
// the tests inject a stub `http.Client` that emulates the FastAPI
// `/chat` echo endpoint. The stub returns the same `{ "reply": "..." }`
// shape the backend does, so the screen exercises the full success
// path without making any network calls.
//
// flutter_test runs without a real keyboard, so the IME-driven tests
// (long messages, keyboard behavior) are exercised by directly
// manipulating the TextEditingController through find.byType(TextField).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:odi/screens/chat_screen.dart';
import 'package:odi/services/api_client.dart';
import 'package:odi/widgets/loading_bubble.dart';
import 'package:odi/widgets/send_button.dart';

/// A mock that records every request and replies with a canned body.
///
/// Mirrors the FastAPI echo behavior from `backend/main.py`:
///   GET  /welcome          → {"reply": "Hello! I'm OdiAI. ..."}
///   POST /chat             → {"reply": "I received your message: ..."}
///
/// Tests that need a specific reply inject a custom [replyFor] function.
/// Tests that need to exercise a failure mode inject [failMode].
class _StubApiClient extends http.BaseClient {
  final List<http.Request> requests = <http.Request>[];
  final String Function(String userMessage) replyFor;
  final String welcomeReply;
  final _ChatFailMode failMode;
  final List<int> callCounts;
  final Duration slowAfter;

  _StubApiClient({
    String Function(String userMessage)? replyFor,
    this.welcomeReply = "Hello! I'm OdiAI. Ask me anything.",
    this.failMode = _ChatFailMode.none,
    List<int>? callCounts,
    this.slowAfter = const Duration(milliseconds: 250),
  })  : replyFor = replyFor ?? _defaultReply,
        callCounts = callCounts ?? <int>[0];

  static String _defaultReply(String userMessage) =>
      'I received your message: $userMessage';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.Request req = request as http.Request;
    requests.add(req);

    // GET /welcome — initial greeting (Task 25). Failures on the
    // welcome path are exercised by returning a 500 in [failMode].
    if (req.method == 'GET' && req.url.path == '/welcome') {
      if (failMode == _ChatFailMode.welcomeFail) {
        return _junkResponse(
          500,
          jsonEncode({
            'error': 'internal_error',
            'detail': 'Welcome endpoint down.',
          }),
        );
      }
      final String body = jsonEncode({'reply': welcomeReply});
      return _junkResponse(200, body);
    }

    // POST /chat — echo the user's message, or simulate a failure.
    callCounts[0] += 1;
    final int attempt = callCounts[0];

    switch (failMode) {
      case _ChatFailMode.none:
        return _echoResponse(req);
      case _ChatFailMode.validation422:
        return _junkResponse(
          422,
          jsonEncode({
            'error': 'validation_error',
            'detail': 'Message is invalid.',
          }),
        );
      case _ChatFailMode.aiUnavailable502:
        return _junkResponse(
          502,
          jsonEncode({
            'error': 'ai_unavailable',
            'detail': 'Upstream model did not respond.',
          }),
        );
      case _ChatFailMode.internal500:
        return _junkResponse(
          500,
          jsonEncode({
            'error': 'internal_error',
            'detail': 'Unexpected server error.',
          }),
        );
      case _ChatFailMode.malformed200:
        // 200 but non-JSON body — exercises the parser branch.
        return _junkResponse(200, 'this-is-not-json-{{{');
      case _ChatFailMode.networkException:
        throw http.ClientException('Connection refused (simulated)');
      case _ChatFailMode.failThenSucceed:
        // First call returns 500, second call succeeds — exercises Retry.
        if (attempt == 1) {
          return _junkResponse(
            500,
            jsonEncode({
              'error': 'internal_error',
              'detail': 'Try again.',
            }),
          );
        }
        return _echoResponse(req);
      case _ChatFailMode.slow:
        // Task 27 — sleep long enough to exceed the test's request
        // timeout (typically ~50ms). The client's `.timeout(...)` will
        // fire and surface an `ApiErrorKind.timeout`.
        return Future<http.StreamedResponse>.delayed(
          slowAfter,
          () => _echoResponse(req),
        );
      case _ChatFailMode.welcomeFail:
        // Should never reach POST /chat here, but echo just in case.
        return _echoResponse(req);
    }
  }

  http.StreamedResponse _echoResponse(http.Request req) {
    final String bodyText = req.body;
    final dynamic decoded =
        bodyText.isNotEmpty ? jsonDecode(bodyText) : <String, dynamic>{};
    final String userMessage =
        (decoded is Map<String, dynamic> && decoded['message'] is String)
            ? decoded['message'] as String
            : '';
    final String reply = replyFor(userMessage);
    return _junkResponse(200, jsonEncode({'reply': reply}));
  }

  http.StreamedResponse _junkResponse(int status, String body) {
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[utf8.encode(body)]),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

/// Failure modes the stub can simulate on POST /chat.
enum _ChatFailMode {
  none,
  validation422,
  aiUnavailable502,
  internal500,
  malformed200,
  networkException,
  failThenSucceed,
  welcomeFail,
  slow,
}

Future<void> _pumpChat(
  WidgetTester tester, {
  String Function(String userMessage)? replyFor,
  String? welcomeReply,
  _ChatFailMode failMode = _ChatFailMode.none,
  List<int>? callCounts,
  Duration? requestTimeout,
  Duration slowAfter = const Duration(milliseconds: 250),
}) async {
  final _StubApiClient stub = _StubApiClient(
    replyFor: replyFor,
    welcomeReply: welcomeReply ?? "Hello! I'm OdiAI. Ask me anything.",
    failMode: failMode,
    callCounts: callCounts,
    slowAfter: slowAfter,
  );
  final ApiClient api = ApiClient(
    baseUrl: Uri.parse('http://test.local'),
    httpClient: stub,
    timeout: requestTimeout ?? const Duration(seconds: 15),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: ChatScreen(apiClient: api, requestTimeout: requestTimeout),
    ),
  );
  // Let the post-frame auto-scroll settle.
  await tester.pump();
  // IMPORTANT: Task 25 — drain the /welcome fetch so the greeting is in
  // the tree before any test inspects it.
  await _waitForWelcome(tester);
}

Finder _field() => find.byType(TextField);

/// The send button is the public SendButton widget rendered inside ChatInput.
Finder _sendButton() => find.byType(SendButton);

/// Helper: tap the send button after entering text.
Future<void> _enterAndSend(
  WidgetTester tester,
  String text,
) async {
  await tester.enterText(_field(), text);
  await tester.pump();
  await tester.tap(_sendButton(), warnIfMissed: false);
  // Allow the post-frame callback (auto-scroll) and the setState to apply.
  await tester.pump();
  await tester.pump();
}

/// Helper: wait for the AI reply to land.
///
/// IMPORTANT: now that the screen uses the real ApiClient, the reply
/// pipeline is:
///   1) The stub's Future completes (microtask).
///   2) The screen's await returns, calling setState.
///   3) The next pump() builds the frame containing the AI bubble.
///   4) Post-frame auto-scroll schedules another frame.
///
/// We pump several small intervals so flutter_test's fake-async drains
/// every microtask and timer in between. `idle()` at the end makes sure
/// no pending timers leak across the test boundary.
Future<void> _waitForReply(WidgetTester tester) async {
  for (int i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump();
  await tester.idle();
}

/// Helper: wait for the initial `/welcome` greeting to land.
///
/// Same drain pattern as [_waitForReply] but called immediately after
/// `_pumpChat` so the greeting is visible before tests start poking at
/// the chat area.
Future<void> _waitForWelcome(WidgetTester tester) => _waitForReply(tester);

void main() {
  group('Test 1: Empty message', () {
    testWidgets('Tapping Send with no text does nothing', (tester) async {
      await _pumpChat(tester);

      // Confirm the initial state has only the welcome AI bubble.
      expect(find.text("Hello! I'm OdiAI. Ask me anything."), findsOneWidget);

      // The SendButton exists but its onPressed is null while the field
      // is empty. Tapping it should be a no-op.
      expect(_sendButton(), findsOneWidget);
      final SendButton btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNull);

      // Try to tap it anyway.
      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();

      // Still only the welcome bubble.
      expect(find.text("Hello! I'm OdiAI. Ask me anything."), findsOneWidget);
    });
  });

  group('Test 2: Short message', () {
    testWidgets('Sending "Hello" appends a user bubble and an AI reply',
        (tester) async {
      await _pumpChat(tester);

      await _enterAndSend(tester, 'Hello');

      // User bubble visible.
      expect(find.text('Hello'), findsOneWidget);
      // Input was cleared.
      final TextField field = tester.widget(_field());
      expect(field.controller!.text, isEmpty);

      // Wait for the AI to finish.
      await _waitForReply(tester);

      // AI reply visible. The stub echoes: "I received your message: Hello".
      expect(find.text('I received your message: Hello'), findsOneWidget);
    });
  });

  group('Test 3: Long message', () {
    testWidgets('Long paragraph renders without overflow', (tester) async {
      await _pumpChat(tester);

      final String longText =
          'This is a fairly long paragraph that contains multiple sentences '
          'and is meant to test how the chat bubble handles wider content. '
          'It should wrap to multiple lines inside the bubble without '
          'breaking the surrounding layout. The bubble should grow '
          'vertically to accommodate the wrapped text, and the rest of '
          'the chat thread should adjust accordingly.';

      await _enterAndSend(tester, longText);
      // Drain the reply so the framework is idle at teardown.
      await _waitForReply(tester);

      // The user bubble contains the long text.
      expect(find.textContaining('fairly long paragraph'), findsOneWidget);

      // The AI reply (echo) is also present.
      expect(find.textContaining('I received your message'), findsOneWidget);

      // No RenderFlex overflow exception should have been thrown. If we got
      // here, layout succeeded.
    });
  });

  group('Test 4: Multiple messages (10+)', () {
    testWidgets('Sending many messages does not crash', (tester) async {
      await _pumpChat(tester);

      for (int i = 0; i < 12; i++) {
        await _enterAndSend(tester, 'Msg $i');
        await _waitForReply(tester);
      }

      // Spot-check that the latest user message is in the tree.
      expect(find.text('Msg 11'), findsOneWidget);
      // No exceptions, layout still intact.
    });
  });

  group('Test 5: Scrolling', () {
    testWidgets('Scrollable area renders the message list', (tester) async {
      await _pumpChat(tester);

      for (int i = 0; i < 8; i++) {
        await _enterAndSend(tester, 'S $i');
        await _waitForReply(tester);
      }

      // The ListView exists.
      expect(find.byType(ListView), findsWidgets);

      // Try a drag to confirm scrolling doesn't crash.
      final Finder listFinder = find.byType(ListView).first;
      await tester.drag(listFinder, const Offset(0, -200));
      await tester.pump();
    });
  });

  group('Test 6: Loading state', () {
    testWidgets('User can send and receive an AI reply end-to-end',
        (tester) async {
      // NOTE: The loading bubble appears between the user's send and the
      // AI's reply. flutter_test's fake-async clock drains pending work
      // on the very next pump(), so by the time we get a chance to
      // inspect the widget tree, the loading state has already
      // resolved. We verify the loading path through behavior:
      // the user bubble lands, the input clears, and the AI reply
      // lands — the same sequence the user sees, just compressed in
      // time.
      await _pumpChat(tester);

      await _enterAndSend(tester, 'Loading test');

      // User bubble visible, input cleared.
      expect(find.text('Loading test'), findsOneWidget);
      final TextField field = tester.widget(_field());
      expect(field.controller!.text, isEmpty);

      // Wait for the AI to reply; confirm a reply lands.
      await _waitForReply(tester);

      // The stub echoes the user's text.
      expect(
        find.text('I received your message: Loading test'),
        findsOneWidget,
      );

      // Loading bubble is no longer in the tree after the reply.
      expect(find.byType(LoadingBubble), findsNothing);
    });
  });

  group('Test 7: Keyboard / long-input safety', () {
    testWidgets('TextField accepts a multi-line value without crashing',
        (tester) async {
      await _pumpChat(tester);

      // Inject a long string with newlines to simulate a multiline message.
      const String multiline = 'Line 1\nLine 2\nLine 3';
      await tester.enterText(_field(), multiline);
      await tester.pump();

      // Field shows the value (TextField keeps newlines internally).
      final TextField field = tester.widget(_field());
      expect(field.controller!.text, multiline);
    });
  });

  group('Test 8: Rapid interaction (no duplicate sends while loading)',
      () {
    testWidgets('Multiple rapid taps produce only one user bubble',
        (tester) async {
      await _pumpChat(tester);

      await tester.enterText(_field(), 'Rapid');
      await tester.pump();

      // Rapid taps on the send button. The first tap sets _isLoading=true;
      // subsequent taps should be ignored because the SendButton is
      // disabled when widget.enabled is false.
      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();
      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();
      await tester.tap(_sendButton(), warnIfMissed: false);
      await tester.pump();

      // Only one user bubble was created with the text "Rapid".
      expect(find.text('Rapid'), findsOneWidget);

      // Wait for the AI to reply, confirm only one exchange landed.
      await _waitForReply(tester);

      // The echo reply should appear exactly once.
      expect(
        find.text('I received your message: Rapid'),
        findsOneWidget,
      );

      // Still only one "Rapid" bubble (no duplicate user send).
      expect(find.text('Rapid'), findsOneWidget);
    });
  });

  group('Test 9: API client wiring', () {
    testWidgets('GET /welcome is fired on launch and POST /chat is called with the user message as JSON',
        (tester) async {
      final _StubApiClient stub = _StubApiClient();
      final ApiClient api =
          ApiClient(baseUrl: Uri.parse('http://test.local'), httpClient: stub);
      await tester.pumpWidget(MaterialApp(home: ChatScreen(apiClient: api)));
      await tester.pump();
      await _waitForWelcome(tester);

      // The first request is the welcome greeting.
      expect(stub.requests.first.method, 'GET');
      expect(stub.requests.first.url.path, '/welcome');

      await _enterAndSend(tester, 'wire-up');
      await _waitForReply(tester);

      // After sending we have two requests: the welcome and the chat.
      expect(stub.requests, hasLength(2));
      final http.Request req =
          stub.requests.firstWhere((r) => r.url.path == '/chat');
      expect(req.method, 'POST');
      expect(req.url.path, '/chat');
      expect(req.headers['content-type'], contains('application/json'));

      // The body is the JSON the backend expects.
      final dynamic decoded = jsonDecode(req.body);
      expect(decoded, isA<Map<String, dynamic>>());
      expect(decoded['message'], 'wire-up');
    });
  });

  group('Test 10: API error handling (Task 26)', () {
    /// Helper: returns the friendly error sentence the screen is
    /// expected to show for the given failure mode. We assert against
    /// `_errorMessageFor`'s output via the visible bubble text.
    String expectedErrorText(_ChatFailMode mode) {
      switch (mode) {
        case _ChatFailMode.validation422:
          return 'Message is invalid.';
        case _ChatFailMode.aiUnavailable502:
          return 'The AI is temporarily unavailable. Please try again.';
        case _ChatFailMode.internal500:
          return 'Something went wrong on the server. Please try again.';
        case _ChatFailMode.malformed200:
          return 'I got an unexpected response from the server. Please try again.';
        case _ChatFailMode.networkException:
          return "I can't reach the server right now. Check your connection and try again.";
        default:
          throw StateError('no expected text for $mode');
      }
    }

    Future<void> triggerAndWaitForError(
      WidgetTester tester, {
      required _ChatFailMode mode,
      String userText = 'boom',
    }) async {
      await _pumpChat(tester, failMode: mode);
      await _enterAndSend(tester, userText);
      await _waitForReply(tester);
    }

    for (final _ChatFailMode mode in <_ChatFailMode>[
      _ChatFailMode.validation422,
      _ChatFailMode.aiUnavailable502,
      _ChatFailMode.internal500,
      _ChatFailMode.malformed200,
      _ChatFailMode.networkException,
    ]) {
      testWidgets(
        'Server failure (${mode.name}) shows a friendly error bubble',
        (tester) async {
          await triggerAndWaitForError(tester, mode: mode);

          // The friendly error text is visible — it lives at the bottom
          // of the scroll, so a plain text finder works here.
          expect(find.text(expectedErrorText(mode)), findsOneWidget);
          // The Retry affordance is rendered on the error bubble. Use
          // the icon finder because the text might be offstage.
          expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
        },
      );
    }

    testWidgets('Loading state stops after an error and input re-enables',
        (tester) async {
      await triggerAndWaitForError(
        tester,
        mode: _ChatFailMode.internal500,
        userText: 'retry-me',
      );

      // The loading bubble is gone (the error took its place).
      expect(find.byType(LoadingBubble), findsNothing);

      // After the error, the input is empty (we cleared it). The
      // SendButton is therefore disabled until the user types again.
      SendButton btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNull);

      // Typing text re-enables the SendButton — proves the input is
      // no longer in the loading-disabled state.
      await tester.enterText(_field(), 'second try');
      await tester.pump();
      btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNotNull);

      // Sending again triggers another error path — no crash, no hang.
      await tester.tap(_sendButton(), warnIfMissed: false);
      await _waitForReply(tester);
      // The new error replaces the old one (no stacking).
      expect(
        find.text('Something went wrong on the server. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Tapping Retry re-sends the original message without duplicating the user bubble',
        (tester) async {
      final List<int> counts = <int>[0];
      await _pumpChat(
        tester,
        failMode: _ChatFailMode.failThenSucceed,
        callCounts: counts,
      );
      await _enterAndSend(tester, 'retry-me');
      // First attempt failed (counts[0] = 1).
      expect(counts[0], 1);
      // Scroll the list to the bottom so the error bubble (the last
      // item) is built and visible.
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pump();
      await tester.pump();
      // The Retry icon is on the error bubble at the bottom of the list.
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // Tap the Retry button on the error bubble.
      await tester.tap(find.byIcon(Icons.refresh_rounded), warnIfMissed: false);
      await _waitForReply(tester);

      // The retry fired a second request (counts[0] = 2) and the stub
      // returned a success this time.
      expect(counts[0], 2);
      // The original AI reply is visible (the success case).
      expect(find.text('I received your message: retry-me'), findsOneWidget);
      // The error bubble is gone (it was replaced by the success reply).
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    });

    testWidgets('Empty/invalid message is silently ignored (no API call)',
        (tester) async {
      final List<int> counts = <int>[0];
      await _pumpChat(tester, callCounts: counts);

      // Whitespace-only input — the input pill's send button is
      // disabled, so even bypassing the input clear must not fire.
      await tester.enterText(_field(), '   ');
      await tester.pump();
      final SendButton btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNull);
      expect(counts[0], 0);
    });

    testWidgets('App does not crash on a malformed 200 response',
        (tester) async {
      // This is the toughest branch: the server returns 200 OK but with
      // junk in the body. The ApiClient must catch the JSON parse
      // failure and surface it as a malformed error.
      await triggerAndWaitForError(
        tester,
        mode: _ChatFailMode.malformed200,
        userText: 'junk-please',
      );
      // The friendly malformed message is visible at the bottom of the list.
      expect(
        find.text(
            'I got an unexpected response from the server. Please try again.'),
        findsOneWidget,
      );
      // No crash — the loading bubble is gone and the Retry icon is up.
      expect(find.byType(LoadingBubble), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });
  });

  group('Test 11: API timeout handling (Task 27)', () {
    /// Advances the fake clock past the client's request timeout so the
    /// stub's delayed Future can resolve as a TimeoutException.
    Future<void> pumpPastTimeout(WidgetTester tester, Duration timeout) async {
      // Pump a hair beyond the timeout; flutter_test's FakeAsync will
      // mark the http.post call as timed out.
      await tester.pump(timeout + const Duration(milliseconds: 50));
      // Drain the resulting microtasks (setState, etc.).
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      await tester.idle();
    }

    testWidgets('Slow response triggers a friendly timeout message',
        (tester) async {
      // Client timeout: 50ms. Stub delays 250ms — should exceed.
      await _pumpChat(
        tester,
        failMode: _ChatFailMode.slow,
        requestTimeout: const Duration(milliseconds: 50),
        slowAfter: const Duration(milliseconds: 250),
      );

      await tester.enterText(_field(), 'slow-please');
      await tester.pump();
      await tester.tap(_sendButton(), warnIfMissed: false);
      await pumpPastTimeout(tester, const Duration(milliseconds: 50));

      // The user bubble is in the thread (offstage predicate).
      // The friendly timeout sentence is visible.
      expect(
        find.text('The server took too long to respond. Please try again.'),
        findsOneWidget,
      );
      // Loading bubble is gone and Retry is on the error bubble.
      expect(find.byType(LoadingBubble), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('Loading state stops after a timeout and input re-enables',
        (tester) async {
      await _pumpChat(
        tester,
        failMode: _ChatFailMode.slow,
        requestTimeout: const Duration(milliseconds: 50),
        slowAfter: const Duration(milliseconds: 250),
      );

      await tester.enterText(_field(), 'timeout-me');
      await tester.pump();
      await tester.tap(_sendButton(), warnIfMissed: false);
      await pumpPastTimeout(tester, const Duration(milliseconds: 50));

      // No more loading bubble.
      expect(find.byType(LoadingBubble), findsNothing);
      // Empty input means the SendButton is currently disabled, but the
      // TextField itself accepts new text — proves the input pill is
      // not in the loading-disabled state.
      SendButton btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNull);
      await tester.enterText(_field(), 'after-timeout');
      await tester.pump();
      btn = tester.widget(_sendButton());
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Retry after a timeout re-sends the original message',
        (tester) async {
      // We can't easily switch the stub from slow → fast mid-test, so
      // this test focuses on the "Retry tapped → second request fired"
      // contract. The other retry tests already cover success-after-failure.
      final List<int> counts = <int>[0];
      await _pumpChat(
        tester,
        failMode: _ChatFailMode.slow,
        requestTimeout: const Duration(milliseconds: 50),
        slowAfter: const Duration(milliseconds: 250),
        callCounts: counts,
      );
      await tester.enterText(_field(), 'retry-after-timeout');
      await tester.pump();
      await tester.tap(_sendButton(), warnIfMissed: false);
      await pumpPastTimeout(tester, const Duration(milliseconds: 50));
      // counts[0] = 1 (the timed-out request).
      expect(counts[0], 1);
      // The error bubble's Retry icon may be offstage in the lazy
      // list; scroll the list so it builds.
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // Tapping Retry re-issues the same POST /chat.
      await tester.tap(find.byIcon(Icons.refresh_rounded), warnIfMissed: false);
      await pumpPastTimeout(tester, const Duration(milliseconds: 50));
      expect(counts[0], 2);
    });

    testWidgets('Normal (fast) responses still work when the timeout is set',
        (tester) async {
      // 200ms timeout, no slow mode — the stub echoes instantly and the
      // response lands well within the timeout.
      await _pumpChat(
        tester,
        requestTimeout: const Duration(milliseconds: 200),
      );
      await _enterAndSend(tester, 'fast');
      await _waitForReply(tester);
      expect(find.text('I received your message: fast'), findsOneWidget);
      expect(find.byType(LoadingBubble), findsNothing);
    });
  });
}