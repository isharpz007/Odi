import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/api_client.dart';
import '../widgets/ai_head.dart';
import '../widgets/chat_input.dart';
import '../widgets/loading_bubble.dart';
import '../widgets/message_bubble.dart';


class ChatScreen extends StatefulWidget {
  /// IMPORTANT: Task 24 — tests inject a fake `ApiClient` (backed by a
  /// stub `http.Client`) so the suite runs offline. Production callers
  /// leave this null and the screen builds the default client.
  final ApiClient? apiClient;

  /// IMPORTANT: Task 27 — per-screen HTTP timeout. Tests override this
  /// with a short duration so the suite doesn't have to wait the full
  /// 15s production timeout. Production callers leave this null and the
  /// screen uses the [ApiClient]'s default (15s).
  final Duration? requestTimeout;

  const ChatScreen({super.key, this.apiClient, this.requestTimeout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // IMPORTANT: Task 25 — the chat starts empty. The first AI bubble is
  // fetched from `GET /welcome` in initState. There is no hardcoded
  // seed message anymore; every assistant line the user sees comes
  // from FastAPI.
  final List<ChatMessage> _messages = <ChatMessage>[];

  /// IMPORTANT: Task 24 — real HTTP client for the FastAPI backend.
  ///
  /// `baseUrl` is resolved by [defaultBaseUrl] which picks the right host
  /// for the current platform (127.0.0.1 on desktop, 10.0.2.2 on Android
  /// emulator). We hold the client for the lifetime of the screen and
  /// close its HTTP client on dispose.
  ///
  /// Tests pass a fake `ApiClient` via [ChatScreen.apiClient]; production
  /// uses the real client wired to the FastAPI backend.
  late final ApiClient _api = widget.apiClient ??
      ApiClient(
        baseUrl: defaultBaseUrl(),
        timeout: widget.requestTimeout ?? const Duration(seconds: 15),
      );

  /// IMPORTANT: Task 17 — tracks whether the user is parked near the bottom
  /// of the chat list. New messages only auto-scroll into view when the
  /// user hasn't intentionally scrolled up to read older messages.
  bool _isAtBottom = true;

  /// IMPORTANT: Task 18 — true while the AI is preparing a reply. Drives
  /// the loading bubble, disables the input, and blocks duplicate sends.
  bool _isLoading = false;

  /// IMPORTANT: Task 25 — true while the initial `/welcome` greeting is
  /// being fetched from the backend. While this is set, the chat list is
  /// empty and the user sees a connecting hint instead of any assistant
  /// text. Once the greeting lands we append it as the first AI message.
  bool _welcomeInFlight = true;

  /// IMPORTANT: Task 38 — the number of history turns to *exclude* from
  /// the next /chat request. The welcome greeting is an AI turn that
  /// comes from the backend, not from the user, but it's still part of
  /// the conversation context Gemini should see. We track how many
  /// leading AI messages (welcome + any prior assistant replies) sit at
  /// the head of the thread so we can compute the slice of messages that
  /// actually represent user/assistant exchange *up to* the user's next
  /// turn.
  ///
  /// Concretely: every prior user send produced exactly one assistant
  /// reply (or one error). When we send the next user message, history
  /// includes everything except the *currently-being-sent* user bubble
  /// and any error bubbles (which aren't real assistant replies).
  /// Cap the history at a reasonable length so we don't blow Gemini's
  /// context window on long sessions.
  static const int _maxHistoryTurns = 40;

  /// Threshold (in logical pixels) for "close enough to the bottom" to count
  /// as being at the bottom. 60px is roughly a single bubble + a little slack.
  static const double _atBottomThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    // Listen for scroll position changes so we know whether the user has
    // intentionally scrolled up to read older messages.
    _scrollController.addListener(_onScrollChanged);
    // Auto-scroll to bottom on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    // IMPORTANT: Task 25 — fetch the greeting from the backend instead
    // of using a hardcoded seed message.
    _loadWelcome();
  }

  /// Asks the backend for the initial greeting and appends it to the
  /// conversation. On failure we fall back to a short "couldn't reach
  /// the server" notice so the chat area is never visually broken.
  Future<void> _loadWelcome() async {
    final ApiResult result = await _api.fetchWelcome();
    if (!mounted) return;
    setState(() {
      _welcomeInFlight = false;
      if (result.error == null) {
        _messages.add(ChatMessage(text: result.reply!, isUser: false));
      } else {
        _messages.add(_errorBubbleFor(result.error!));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Builds an error bubble from an [ApiError]. The retry callback is
  /// null because the welcome greeting has no associated user message
  /// to re-send; only user-driven errors get a Retry button.
  ChatMessage _errorBubbleFor(ApiError error) {
    return ChatMessage(
      text: _errorMessageFor(error),
      isUser: false,
      isError: true,
    );
  }

  /// IMPORTANT: Task 38 — gathers prior conversation turns for the
  /// next /chat request. Walks the existing message list in order and
  /// converts each non-error ChatMessage into a HistoryTurn:
  ///
  ///   user message       → HistoryTurn(role: 'user',      text: …)
  ///   AI / welcome reply → HistoryTurn(role: 'assistant', text: …)
  ///
  /// We deliberately drop error bubbles — they're UI scaffolding, not
  /// real assistant replies, and including them would confuse Gemini
  /// ("assistant said: I can't reach the server right now…").
  ///
  /// The list is capped at [_maxHistoryTurns] (most recent turns) so
  /// long sessions don't blow Gemini's context window.
  List<HistoryTurn> _buildHistoryForSend() {
    final List<HistoryTurn> turns = <HistoryTurn>[];
    for (final ChatMessage m in _messages) {
      if (m.isError) continue;
      turns.add(HistoryTurn(role: m.isUser ? 'user' : 'assistant', text: m.text));
    }
    if (turns.length > _maxHistoryTurns) {
      return turns.sublist(turns.length - _maxHistoryTurns);
    }
    return turns;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
    _api.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // IMPORTANT: only count "at bottom" when the pixels remaining to scroll
    // are within the threshold. This handles overscroll/bounce correctly.
    final bool atBottom = (pos.maxScrollExtent - pos.pixels) <= _atBottomThreshold;
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    // IMPORTANT: only auto-scroll when the user is already near the bottom.
    // If they scrolled up to read older messages, leave them alone — their
    // scroll position is intentional and yanking them back would be jarring.
    if (!_isAtBottom) return;
    if (!_scrollController.hasClients) return;
    final double target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  /// Called by the chat input when the user taps Send.
  /// IMPORTANT: Task 18 — when called, this method:
  ///   1) Rejects the send if a previous request is still in-flight
  ///      (prevents duplicate sends while loading).
  ///   2) Appends the user bubble and clears the input.
  ///   3) Sets _isLoading = true so the loading bubble appears and the
  ///      input pill becomes non-interactive.
  ///   4) Awaits the real AI reply (POST /chat via ApiClient), then
  ///      replaces the loading bubble with the AI message and clears
  ///      _isLoading.
  ///
  /// IMPORTANT: Task 24 — every assistant reply comes from FastAPI's
  /// `/chat` endpoint (wire format documented in
  /// `backend/API_DESIGN.md`). The server currently echoes the message
  /// back; Milestone 4 will swap the AI implementation.
  Future<void> _onUserSend(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // IMPORTANT: duplicate-send guard. If a previous request is still
    // in-flight, ignore this tap entirely. The input pill is also
    // disabled via `enabled: !_isLoading`, but this is a belt-and-
    // suspenders check for race conditions.
    if (_isLoading) return;

    await _dispatchUserSend(trimmed, isRetry: false);
  }

  /// Shared body for a user-driven send. When [isRetry] is false we
  /// append a fresh user bubble and clear the input; when true we
  /// re-send the same text without duplicating the user bubble or
  /// clearing the input (the input is already empty by the time we
  /// retry anyway).
  Future<void> _dispatchUserSend(String text, {required bool isRetry}) async {
    // IMPORTANT: Task 38 — capture the history slice *before* we append
    // the new user bubble to `_messages`. `_buildHistoryForSend` walks
    // `_messages`, so if we ran it after the append it would include
    // the just-sent user text in the history; the request body would
    // then carry that turn in `history` AND repeat it as the trailing
    // `message` field, producing a double-user-turn and breaking
    // Gemini's strict user/model alternation.
    final history = _buildHistoryForSend();

    // 1) Append the user bubble, clear the input, flip loading on.
    //    On a retry, the user bubble is already in the thread — skip
    //    the append and the input clear.
    setState(() {
      if (!isRetry) {
        _messages.add(ChatMessage(text: text, isUser: true));
        _controller.clear();
      }
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 2) Hit the real backend. While we wait, the build method renders
    //    a LoadingBubble at the end of the list because _isLoading is
    //    true. ApiClient never throws — failures are surfaced via
    //    ApiResult.fail(ApiErrorKind, ...).
    //
    //    IMPORTANT: Task 38 — include prior conversation turns so
    //    Gemini can answer follow-ups. Captured above before the user
    //    bubble was appended.
    //
    //    IMPORTANT: Task 38½ — switch to streaming. We append an empty
    //    AI bubble immediately and grow it as token chunks arrive, so
    //    the user sees text appear with a typewriter effect instead of
    //    staring at "OdiAI is thinking…" for the whole generation.

    // Helper: pop the trailing error bubble if this is a retry, so we
    // don't end up with error-on-error stacking.
    void popTrailingError() {
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].isError) {
          _messages.removeAt(i);
          break;
        }
      }
    }

    // Append an empty AI bubble we'll grow with streamed chunks.
    final int aiBubbleIndex;
    if (isRetry) {
      popTrailingError();
      final bubble = ChatMessage(text: '', isUser: false);
      _messages.add(bubble);
      aiBubbleIndex = _messages.length - 1;
    } else {
      final bubble = ChatMessage(text: '', isUser: false);
      _messages.add(bubble);
      aiBubbleIndex = _messages.length - 1;
    }
    // Drop the loading indicator now that the placeholder bubble is in
    // place — the user can see "the AI is composing its reply" via the
    // empty bubble that grows as tokens arrive.
    setState(() => _isLoading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    if (!mounted) return;

    Object? streamError;
    try {
      await for (final String chunk in _api.sendMessageStream(
        text,
        history: history,
      )) {
        if (!mounted) return;
        setState(() {
          final cur = _messages[aiBubbleIndex];
          _messages[aiBubbleIndex] = ChatMessage(
            text: cur.text + chunk,
            isUser: false,
            id: cur.id,
          );
        });
        // Keep the latest text visible while it streams in.
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } on ApiError catch (e) {
      streamError = e;
    } catch (e) {
      // ApiClient streams errors through Stream.addError; in case any
      // other exception escapes the stream, normalize to aiUnavailable.
      streamError = ApiError(ApiErrorKind.aiUnavailable, '$e');
    }

    if (!mounted) return;

    // 3) If the stream produced an error, replace the empty/partial AI
    //    bubble with an error bubble so the user gets a clear Retry.
    if (streamError is ApiError) {
      setState(() {
        _messages.removeAt(aiBubbleIndex);
        final errBubble = ChatMessage(
          text: _errorMessageFor(streamError as ApiError),
          isUser: false,
          isError: true,
        );
        if (isRetry) {
          // Replace the previous error bubble we already popped.
          // (We popped before adding the streaming bubble, so just
          // append a fresh error.)
          _messages.add(errBubble);
        } else {
          _messages.add(errBubble);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } else {
      // Empty stream with no error: surface a friendly "the AI didn't
      // produce a reply" notice rather than showing a blank bubble.
      if (_messages.isNotEmpty && _messages[aiBubbleIndex].text.trim().isEmpty) {
        setState(() {
          _messages.removeAt(aiBubbleIndex);
          _messages.add(ChatMessage(
            text: "I didn't get a reply. Please try again.",
            isUser: false,
            isError: true,
          ));
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    }
  }

  /// IMPORTANT: Task 26 — retry handler attached to the Retry button
  /// inside an error bubble. Walks back from the error bubble to find
  /// the most recent user message (the one that triggered the failed
  /// request) and re-sends its text.
  ///
  /// We rely on the rule that error bubbles always sit immediately
  /// after their triggering user bubble, so a backward scan that
  /// stops at the first `isUser` bubble is correct.
  Future<void> _retry(ChatMessage errorBubble) async {
    if (_isLoading) return;
    String? lastUserText;
    for (int i = _messages.length - 1; i >= 0; i--) {
      final ChatMessage m = _messages[i];
      if (m.id == errorBubble.id) continue; // skip the error bubble itself
      if (m.isUser) {
        lastUserText = m.text;
        break;
      }
      if (m.isError) continue; // skip older error bubbles
    }
    if (lastUserText == null || lastUserText.trim().isEmpty) return;
    await _dispatchUserSend(lastUserText, isRetry: true);
  }

  /// Maps an [ApiError] to a short user-facing sentence shown inside an
  /// AI-styled error bubble. The error kind controls the wording so the
  /// UI can branch without parsing the raw `detail` string.
  String _errorMessageFor(ApiError error) {
    switch (error.kind) {
      case ApiErrorKind.timeout:
        return "The server took too long to respond. Please try again.";
      case ApiErrorKind.network:
        return "I can't reach the server right now. Check your connection and try again.";
      case ApiErrorKind.validation:
        return error.detail.isNotEmpty
            ? error.detail
            : "That message couldn't be sent. Please try again.";
      case ApiErrorKind.aiUnavailable:
        return "The AI is temporarily unavailable. Please try again.";
      case ApiErrorKind.malformed:
        return "I got an unexpected response from the server. Please try again.";
      case ApiErrorKind.internal:
        return "Something went wrong on the server. Please try again.";
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final headSize = (screenWidth * 0.22).clamp(96.0, 136.0);
    final paddingTop = (screenHeight * 0.10).clamp(48.0, 96.0);
    final paddingBottom = (screenHeight * 0.06).clamp(28.0, 56.0);
    final inputPaddingH = (screenWidth * 0.05).clamp(16.0, 28.0);

    return Scaffold(
      body: Stack(
        children: [
          // root background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.10),
                  radius: 0.9,
                  colors: [
                    Color(0xFF050D20),
                    Color(0xFF020810),
                    Colors.black,
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // bgGlow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.05,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 600,
                height: 600,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color.fromRGBO(25, 80, 200, 0.1), Colors.transparent],
                    stops: [0.0, 0.70],
                  ),
                ),
              ),
            ),
          ),
          // bgGlowLower
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 800,
                height: 600,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color.fromRGBO(20, 60, 180, 0.08), Colors.transparent],
                    stops: [0.0, 0.70],
                  ),
                ),
              ),
            ),
          ),
          // main content
          Padding(
            padding: EdgeInsets.only(top: paddingTop, bottom: paddingBottom),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // IMPORTANT: Task 17 — the chat list is now an Expanded flex
                // child. The head + dome take their preferred size at the
                // top; the input pill takes its preferred size at the bottom;
                // everything in between is given to the scrollable list, so
                // the list always scrolls when content overflows.
                //
                // IMPORTANT: Task 19 + Task 38 cleanup — only the
                // AiHeadWidget remains; the body "belly" and the center
                // belly-button were removed. The head still overflows
                // its declared bounds via clipBehavior: none (the
                // halo + glow extend past the head circle), so we
                // give the dome a generous safety margin before deciding
                // to render it; otherwise we hide it entirely and let the
                // chat area use the full vertical space.
                //
                // Reserve room for the input pill (~80 px on a small viewport
                // because the TextField + send button + padding add up) and
                // the head's halo slop (~80 px).
                final inputReservedHeight = 80.0;
                final domeOverflowSlop = 80.0;
                final domeBudget = (constraints.maxHeight -
                        inputReservedHeight -
                        domeOverflowSlop)
                    .clamp(0.0, 9999.0);

                // Only show the head when there's enough room for it and
                // its halo. Otherwise hide it so the chat list gets the
                // full vertical space.
                //
                // IMPORTANT: Task 38 cleanup — the body "belly" and the
                // center belly-button are gone. Only the head remains.
                // The dome-budget check still uses the head's halo slop
                // (the head's animation/glow can extend past its declared
                // bounds via clipBehavior: none) so the chat list isn't
                // pushed off-screen.
                final bool showHead = domeBudget > headSize + 32.0;

                return Column(
                  children: [
                    // top: head alone, centered horizontally
                    if (showHead)
                      Center(child: AiHeadWidget(size: headSize)),
                    // middle: message thread expands to fill remaining space.
                    // IMPORTANT: Expanded gives the list a fixed bounded
                    // viewport, which lets ListView.builder scroll properly.
                    // shrinkWrap is intentionally OFF so the list scrolls
                    // natively instead of overflowing the column.
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(
                              horizontal: inputPaddingH,
                              vertical: 8,
                            ),
                            // IMPORTANT: Task 18 — when the AI is preparing
                            // a reply, append a LoadingBubble after the
                            // existing messages so the user gets visual
                            // feedback that something is happening.
                            itemCount: _messages.length + (_isLoading ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index < _messages.length) {
                                final ChatMessage m = _messages[index];
                                return MessageBubble(
                                  message: m,
                                  onRetry: m.isError ? () => _retry(m) : null,
                                );
                              }
                              // Last slot while loading: animated indicator.
                              return const LoadingBubble();
                            },
                          ),
                          // IMPORTANT: Task 25 — while the welcome greeting
                          // is in flight from the backend, show a small
                          // "connecting" hint centred in the empty chat area
                          // so the screen doesn't look broken on launch.
                          if (_welcomeInFlight)
                            Center(
                              child: _ConnectingHint(),
                            ),
                          // IMPORTANT: a "jump to latest" affordance that
                          // appears only when the user has scrolled up to
                          // read older messages. Tapping it scrolls back to
                          // the bottom. Hidden when already at the bottom.
                          if (!_isAtBottom)
                            Positioned(
                              right: inputPaddingH,
                              bottom: 8,
                              child: _JumpToLatestButton(
                                onTap: () {
                                  _scrollToBottom(animated: true);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    // bottom: chat input pill (fixed — never scrolls)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inputPaddingH),
                      child: Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: ChatInput(
                              controller: _controller,
                              // IMPORTANT: wires the input pill's send tap to
                              // the chat thread. Task 15 — displays user
                              // messages. No FastAPI / AI call yet.
                              onSend: _onUserSend,
                              // IMPORTANT: Task 18 — disable the input pill
                              // while the AI is preparing a reply so the
                              // user can't fire a duplicate send.
                              enabled: !_isLoading,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// IMPORTANT: Task 25 — small placeholder shown while the initial
/// `/welcome` greeting is being fetched from the backend. It only
/// covers the empty chat area and disappears as soon as the greeting
/// lands. We deliberately keep it visually quiet (no spinner) so it
/// doesn't fight with the dome glow.
class _ConnectingHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Connecting to OdiAI…',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: const Color.fromRGBO(140, 200, 255, 0.55),
            fontSize: 13,
            fontStyle: FontStyle.italic,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// IMPORTANT: Task 17 — small floating button that appears when the user
/// scrolls up to read older messages. Tapping it returns the list to the
/// most recent message at the bottom of the conversation.
class _JumpToLatestButton extends StatelessWidget {
  final VoidCallback onTap;
  const _JumpToLatestButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color.fromRGBO(10, 18, 45, 0.85),
          border: Border.all(
            color: const Color.fromRGBO(55, 180, 255, 0.55),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(30, 120, 255, 0.35),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Color.fromRGBO(140, 210, 255, 0.95),
          size: 22,
        ),
      ),
    );
  }
}
