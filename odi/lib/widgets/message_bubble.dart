import 'package:flutter/material.dart';
import '../models/chat_message.dart';

/// Renders a chat bubble. Three visual modes:
///
///   - User bubble: right-aligned, bright cyan border.
///   - AI bubble:   left-aligned, dim cyan border.
///   - Error bubble (Task 26): left-aligned like AI, but with a warm-red
///     border, an "Error" label, and an optional Retry button.
///
/// The Retry button is only shown when [onRetry] is non-null. Callers
/// pass it through from the chat screen when the bubble represents a
/// failed request that the user should be able to resend.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const MessageBubble({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.isUser;
    final bool isError = message.isError;

    final Color borderColor = isError
        ? const Color.fromRGBO(255, 110, 110, 0.75)
        : isUser
            ? const Color.fromRGBO(90, 205, 255, 0.7)
            : const Color.fromRGBO(70, 190, 255, 0.5);

    final Color textColor = isError
        ? const Color.fromRGBO(255, 220, 220, 0.95)
        : const Color.fromRGBO(200, 222, 245, 0.92);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isError
                  ? const [
                      Color.fromRGBO(45, 12, 18, 0.92),
                      Color.fromRGBO(28, 6, 12, 0.94),
                    ]
                  : const [
                      Color.fromRGBO(10, 18, 45, 0.88),
                      Color.fromRGBO(4, 8, 22, 0.92),
                    ],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isUser ? 22 : 6),
              topRight: Radius.circular(isUser ? 6 : 22),
              bottomLeft: const Radius.circular(22),
              bottomRight: const Radius.circular(22),
            ),
            border: Border.all(
              color: borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isError
                    ? const Color.fromRGBO(255, 80, 80, 0.18)
                    : const Color.fromRGBO(30, 120, 255, 0.18),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: Color.fromRGBO(255, 160, 160, 0.95),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Error',
                        style: TextStyle(
                          color: Color.fromRGBO(255, 160, 160, 0.95),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                message.text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  height: 1.35,
                  letterSpacing: 0.1,
                ),
              ),
              if (isError && onRetry != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _RetryButton(onPressed: onRetry!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small inline "Retry" pill rendered beneath an error bubble.
class _RetryButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _RetryButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color.fromRGBO(255, 160, 160, 0.55),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.refresh_rounded,
                size: 14,
                color: Color.fromRGBO(255, 200, 200, 0.95),
              ),
              SizedBox(width: 6),
              Text(
                'Retry',
                style: TextStyle(
                  color: Color.fromRGBO(255, 200, 200, 0.95),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}