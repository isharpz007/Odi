import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Circular send button matching the Figma design.
///
/// IMPORTANT:
/// - This button is wired to the message input only. It does NOT call any
///   backend, FastAPI endpoint, or AI service. When `onPressed` is `null`
///   the button is disabled (dimmed, no glow, no tap response).
/// - When the input has text, the parent passes a non-null `onPressed`.
///   At this milestone that callback is a temporary test action (e.g. a
///   `debugPrint`) — no network call is made.
class SendButton extends StatefulWidget {
  /// IMPORTANT: pass `null` when the message input is empty so the button
  /// renders in its disabled state. Pass a callback (the test action for
  /// this milestone) once the input has content.
  final VoidCallback? onPressed;

  const SendButton({super.key, this.onPressed});

  @override
  State<SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<SendButton>
    with SingleTickerProviderStateMixin {
  // IMPORTANT: drives the brief press-down scale animation for tap feedback.
  late final AnimationController _pressController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 140),
    lowerBound: 0.0,
    upperBound: 1.0,
  );

  late final Animation<double> _pressScale = Tween<double>(
    begin: 1.0,
    end: 0.92,
  ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  bool get _isEnabled => widget.onPressed != null;

  void _handleTap() {
    // IMPORTANT: no backend / FastAPI / AI call here. This milestone only
    // verifies that the tap reaches the test action wired up by the parent.
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  void _handleTapDown(TapDownDetails _) {
    if (!_isEnabled) return;
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails _) {
    if (!_isEnabled) return;
    _pressController.reverse();
  }

  void _handleTapCancel() {
    if (!_isEnabled) return;
    _pressController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // Disabled state: muted appearance — no glow, dim rim, low-opacity icon.
    // Enabled state: full Figma glow stack, bright cyan rim, bright icon.
    final enabled = _isEnabled;

    // IMPORTANT: glow + rim opacities are gated on `enabled` so the button
    // visually communicates "you can't send yet" when the input is empty.
    final rimOpacity = enabled ? 0.22 : 0.08;
    final glowOuter = enabled
        ? const Color.fromRGBO(60, 190, 255, 0.55)
        : const Color.fromRGBO(60, 190, 255, 0.0);
    final glowMid = enabled
        ? const Color.fromRGBO(40, 160, 255, 0.30)
        : const Color.fromRGBO(40, 160, 255, 0.0);
    final glowFar = enabled
        ? const Color.fromRGBO(20, 100, 220, 0.18)
        : const Color.fromRGBO(20, 100, 220, 0.0);
    final iconColor = enabled
        ? const Color.fromRGBO(140, 210, 255, 0.95)
        : const Color.fromRGBO(140, 210, 255, 0.30);

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send message',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: enabled ? _handleTap : null,
        child: AnimatedBuilder(
          animation: _pressScale,
          builder: (context, child) =>
              Transform.scale(scale: _pressScale.value, child: child),
          child: Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // IMPORTANT: fill gradient stays the same in both states —
              // only the surrounding glow changes. This matches the Figma
              // design where the disabled look is "dim", not "different color".
              gradient: const RadialGradient(
                center: Alignment(-0.24, -0.40),
                colors: [
                  Color.fromRGBO(18, 38, 80, 0.95),
                  Color.fromRGBO(4, 8, 22, 0.98),
                  Color.fromRGBO(1, 2, 8, 1),
                ],
                stops: [0.0, 0.60, 1.0],
              ),
              boxShadow: [
                BoxShadow(color: glowOuter, blurRadius: 0, spreadRadius: 1),
                BoxShadow(color: glowMid, blurRadius: 12, spreadRadius: 3),
                BoxShadow(color: glowFar, blurRadius: 32, spreadRadius: 8),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // sendBtnInner — soft inner highlight, fades when disabled.
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: Alignment(-0.24, -0.40),
                      colors: [
                        Color.fromRGBO(
                          32,
                          75,
                          165,
                          enabled ? 0.25 : 0.06,
                        ),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.65],
                    ),
                  ),
                ),
                // sendBtnRim — thin cyan ring around the button.
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Color.fromRGBO(90, 210, 255, rimOpacity),
                      width: 1,
                    ),
                  ),
                ),
                // SendIcon — paper-plane glyph from the Figma frame.
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CustomPaint(
                    painter: _SendIconPainter(color: iconColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SendIconPainter extends CustomPainter {
  final Color color;
  const _SendIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);

    // IMPORTANT: icon stroke color reflects the enabled/disabled state so
    // a glance at the icon tells the user whether tapping will do anything.
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // line x1=22 y1=2 x2=11 y2=13
    canvas.drawLine(const Offset(22, 2), const Offset(11, 13), paint);

    // polygon 22,2 15,22 11,13 2,9
    final path = Path()
      ..moveTo(22, 2)
      ..lineTo(15, 22)
      ..lineTo(11, 13)
      ..lineTo(2, 9)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SendIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
