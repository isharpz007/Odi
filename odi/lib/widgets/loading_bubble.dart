import 'package:flutter/material.dart';

/// IMPORTANT: Task 18 — visual loading indicator shown in the chat thread
/// while the AI is preparing a reply. Styled to match the AI message
/// bubble (left-aligned, dim cyan border, dark glass gradient) so it reads
/// as "AI is talking" rather than "user is typing".
///
/// Uses three pulsing dots that fade in/out in sequence to give the
/// impression of activity without a busy spinner.
class LoadingBubble extends StatefulWidget {
  const LoadingBubble({super.key});

  @override
  State<LoadingBubble> createState() => _LoadingBubbleState();
}

class _LoadingBubbleState extends State<LoadingBubble>
    with SingleTickerProviderStateMixin {
  // IMPORTANT: drives the three pulsing dots. Each dot's opacity is
  // computed from a single shared animation value so the dots pulse in
  // sequence (0→1→2→0) with a small phase offset between them.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.fromRGBO(10, 18, 45, 0.88),
                Color.fromRGBO(4, 8, 22, 0.92),
              ],
            ),
            // AI bubble radius pattern: bottom-left + bottom-right rounded,
            // top-right rounded, top-left sharp (the "tail" corner).
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(22),
              bottomLeft: Radius.circular(22),
              bottomRight: Radius.circular(22),
            ),
            border: Border.all(
              color: const Color.fromRGBO(70, 190, 255, 0.5),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(30, 120, 255, 0.18),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      // Phase-offset each dot so they pulse in sequence.
                      final double t =
                          (_controller.value + i / 3.0) % 1.0;
                      // Smooth bell curve: 0→1→0 over each cycle.
                      final double pulse =
                          0.4 + 0.6 * (0.5 - 0.5 * (2 * t - 1).abs());
                      return Padding(
                        padding: EdgeInsets.only(
                          right: i < 2 ? 6 : 0,
                        ),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.fromRGBO(140, 210, 255, pulse),
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(80, 180, 255, pulse * 0.7),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
              const SizedBox(width: 12),
              const Text(
                'OdiAI is thinking…',
                style: TextStyle(
                  color: Color.fromRGBO(180, 210, 240, 0.7),
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
