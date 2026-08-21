import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../widgets/ai_head.dart';
import '../widgets/ai_body.dart';
import '../widgets/center_control.dart';
import '../widgets/chat_input.dart';
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

  @override
  void initState() {
    super.initState();
    // Auto-scroll to bottom whenever the thread grows.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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
                // Body scales to the remaining space after head + input.
                // We let Flutter's flex layout do the math (no hand-computed
                // reservations), so the Column is guaranteed to fit.
                final domeBudget = constraints.maxHeight - 80; // input + breathing room
                final bodySize = (domeBudget - headSize)
                    .clamp(64.0, maxBodySize);

                return Column(
                  children: [
                    // top: head + body dome at preferred size
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
                    // middle: message thread expands to fill remaining space.
                    // Flexible(fit: FlexFit.loose) lets it shrink to 0 if the
                    // dome + input already fill the column.
                    Flexible(
                      fit: FlexFit.loose,
                      child: ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        padding: EdgeInsets.symmetric(
                          horizontal: inputPaddingH,
                          vertical: 8,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(message: _messages[index]);
                        },
                      ),
                    ),
                    // bottom: chat input pill
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: inputPaddingH),
                      child: Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 480),
                            child: ChatInput(
                              controller: _controller,
                              onSend: _send,
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
