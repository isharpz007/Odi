import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'send_button.dart';

class ChatInput extends StatefulWidget {
  final TextEditingController? controller;

  /// Called when the user taps Send with non-empty text.
  /// The text that was typed is passed in so the parent can append it to
  /// the chat thread. The input itself does NOT clear the field — that's
  /// the parent's responsibility, so the order of "append message → clear
  /// input" stays consistent with one source of truth.
  final ValueChanged<String>? onSend;

  /// IMPORTANT: Task 18 — when false, the input is non-interactive (the
  /// text field and send button are disabled and visually dimmed). The
  /// parent uses this to prevent duplicate sends while the AI is
  /// processing a previous message.
  final bool enabled;
  const ChatInput({
    super.key,
    this.controller,
    this.onSend,
    this.enabled = true,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_onTextChanged);
      _controller.dispose();
      _controller = widget.controller ?? TextEditingController();
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _handleSend() {
    // IMPORTANT: gate on the parent's `enabled` flag too, so a disabled
    // input (e.g. while the AI is processing) cannot fire a send tap.
    if (!widget.enabled) return;
    if (!_canSend) return;
    HapticFeedback.lightImpact();

    // IMPORTANT: hand the typed text to the parent via `onSend`. The parent
    // (ChatScreen) is responsible for appending it to the chat thread and
    // clearing the field. We deliberately do NOT clear the field here so
    // there is one source of truth for the clear-after-append order.
    final String text = _controller.text;
    debugPrint('[ChatInput] sending: "$text"');
    widget.onSend?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxInputWidth = constraints.maxWidth.clamp(220.0, 520.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // inputGlow
            Positioned(
              top: -16,
              left: -16,
              right: -16,
              bottom: -16,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(80),
                    gradient: const RadialGradient(
                      colors: [
                        Color.fromRGBO(40, 130, 255, 0.18),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.65],
                    ),
                  ),
                ),
              ),
            ),
            // inputPill
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxInputWidth),
              child: IgnorePointer(
                ignoring: !widget.enabled,
                child: ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 6, 6, 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(60),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.fromRGBO(10, 18, 45, 0.88),
                          Color.fromRGBO(4, 8, 22, 0.92),
                        ],
                      ),
                      border: Border.all(
                        color: const Color.fromRGBO(55, 180, 255, 0.48),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromRGBO(30, 120, 255, 0.2),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                        BoxShadow(
                          color: Color.fromRGBO(15, 60, 180, 0.1),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: 40,
                              maxHeight: 120,
                            ),
                            child: TextField(
                              controller: _controller,
                              enabled: widget.enabled,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              style: TextStyle(
                                color: widget.enabled
                                    ? const Color.fromRGBO(200, 222, 245, 0.92)
                                    : const Color.fromRGBO(200, 222, 245, 0.45),
                                fontSize: 15,
                                letterSpacing: 0.15,
                                height: 1.35,
                              ),
                              cursorColor: const Color.fromRGBO(
                                80,
                                180,
                                255,
                                0.85,
                              ),
                              cursorWidth: 1.4,
                              decoration: InputDecoration(
                                hintText: 'Message...',
                                hintStyle: const TextStyle(
                                  color: Color.fromRGBO(180, 210, 240, 0.45),
                                  fontSize: 15,
                                  letterSpacing: 0.15,
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 11,
                                  horizontal: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: SendButton(
                            // IMPORTANT: send is disabled both when the
                            // input is empty AND when the parent has marked
                            // the input as disabled (loading state).
                            onPressed: (widget.enabled && _canSend)
                                ? _handleSend
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),
            ),
          ],
        );
      },
    );
  }
}
