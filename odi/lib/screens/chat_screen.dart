import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../widgets/ai_head.dart';
import '../widgets/ai_body.dart';
import '../widgets/center_control.dart';
import '../widgets/chat_input.dart';
import '../widgets/loading_bubble.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[
    const ChatMessage(text: 'Hello! How can I help you today?', isUser: false),
  ];

  /// IMPORTANT: Task 17 — tracks whether the user is parked near the bottom
  /// of the chat list. New messages only auto-scroll into view when the
  /// user hasn't intentionally scrolled up to read older messages.
  bool _isAtBottom = true;

  /// IMPORTANT: Task 18 — true while the (mock) AI is "thinking". Drives
  /// the loading bubble, disables the input, and blocks duplicate sends.
  bool _isLoading = false;

  /// Threshold (in logical pixels) for "close enough to the bottom" to count
  /// as being at the bottom. 60px is roughly a single bubble + a little slack.
  static const double _atBottomThreshold = 60.0;

  /// IMPORTANT: mock AI service — Task 16 only. Returns a canned reply
  /// derived from the user's text. There is NO real AI, no FastAPI call,
  /// and no network traffic. Replace with the real backend client in a
  /// later task.
  Future<String> _mockAiReply(String userText) async {
    // Simulate the AI "thinking" so the UI exercises the loading state.
    // Using Future.delayed so the call respects the Flutter scheduler and
    // is intercepted by flutter_test's FakeAsync (advances via pump).
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final String lower = userText.trim().toLowerCase();
    if (lower.isEmpty) return 'Hello! How can I help you today?';
    if (lower.contains('hello') || lower.contains('hi')) {
      return 'Hello! How can I help you today?';
    }
    if (lower.contains('?')) {
      return "That's a great question — here's what I'd suggest…";
    }
    return "Got it — tell me more and I'll dig in.";
  }

  @override
  void initState() {
    super.initState();
    // Listen for scroll position changes so we know whether the user has
    // intentionally scrolled up to read older messages.
    _scrollController.addListener(_onScrollChanged);
    // Auto-scroll to bottom on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _controller.dispose();
    _scrollController.dispose();
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

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// Called by the chat input when the user taps Send.
  /// IMPORTANT: Task 18 — when called, this method:
  ///   1) Rejects the send if a previous request is still in-flight
  ///      (prevents duplicate sends while loading).
  ///   2) Appends the user bubble and clears the input.
  ///   3) Sets _isLoading = true so the loading bubble appears and the
  ///      input pill becomes non-interactive.
  ///   4) Awaits the (mock) AI reply, then replaces the loading bubble
  ///      with the real AI message and clears _isLoading.
  /// No real AI / FastAPI yet — that's a later task.
  Future<void> _onUserSend(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // IMPORTANT: duplicate-send guard. If the AI is still preparing a
    // reply to the previous message, ignore this tap entirely. The input
    // pill is also disabled via `enabled: !_isLoading`, but this is a
    // belt-and-suspenders check for race conditions.
    if (_isLoading) return;

    // 1) Append the user's bubble, clear the input, and flip loading on.
    setState(() {
      _messages.add(ChatMessage(text: trimmed, isUser: true));
      _controller.clear();
      _isLoading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // 2) Ask the mock AI for a reply. While we wait, the build method
    //    renders a LoadingBubble at the end of the list because
    //    _isLoading is true.
    final String reply = await _mockAiReply(trimmed);
    if (!mounted) return;

    // 3) Replace the loading state with the real AI reply.
    setState(() {
      _isLoading = false;
      _messages.add(ChatMessage(text: reply, isUser: false));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final headSize = (screenWidth * 0.22).clamp(96.0, 136.0);
    final maxBodySize = screenWidth < 580 ? screenWidth * 0.94 : 580.0;
    final centerBtnSize = (screenWidth * 0.12).clamp(52.0, 68.0);
    final paddingTop = (screenHeight * 0.10).clamp(48.0, 96.0);
    final paddingBottom = (screenHeight * 0.06).clamp(28.0, 56.0);
    final inputPaddingH = (screenWidth * 0.05).clamp(16.0, 28.0);

    final bodyMarginTop = (-screenWidth * 0.10).clamp(-60.0, -40.0);

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
                // IMPORTANT: Task 19 — the dome's widgets (AiHeadWidget +
                // AiBodyWidget + CenterControl) report intrinsic heights
                // that don't always match what they paint (the body's halo
                // and the center button overflow via clipBehavior: none).
                // We give the dome a generous safety margin before deciding
                // to render it; otherwise we hide it entirely and let the
                // chat area use the full vertical space.
                //
                // Reserve room for the input pill (~80 px on a small viewport
                // because the TextField + send button + padding add up) and
                // the dome's overflow slop (~80 px for the body halo +
                // center button extending past its declared bounds).
                final inputReservedHeight = 80.0;
                final domeOverflowSlop = 80.0;
                final domeBudget = (constraints.maxHeight -
                        inputReservedHeight -
                        domeOverflowSlop)
                    .clamp(0.0, 9999.0);
                final bodySize =
                    (domeBudget - headSize - 56.0).clamp(0.0, maxBodySize);

                // Only show the dome when there's enough room for the head,
                // its halo, and a non-trivial body. Otherwise hide it so the
                // chat area gets the full vertical space.
                final bool showDome = bodySize > 32.0;

                return Column(
                  children: [
                    // top: head + body dome at preferred size
                    if (showDome) ...[
                      AiHeadWidget(size: headSize),
                      Transform.translate(
                        offset: Offset(0, bodyMarginTop),
                        child: AiBodyWidget(
                          size: bodySize,
                          child: CenterControl(
                            size: centerBtnSize,
                            onTap: _send,
                          ),
                        ),
                      ),
                    ],
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
                                return MessageBubble(message: _messages[index]);
                              }
                              // Last slot while loading: animated indicator.
                              return const LoadingBubble();
                            },
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
