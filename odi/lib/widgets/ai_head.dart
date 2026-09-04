import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AiHeadWidget extends StatefulWidget {
  final double size;
  const AiHeadWidget({super.key, required this.size});

  @override
  State<AiHeadWidget> createState() => _AiHeadWidgetState();
}

class _AiHeadWidgetState extends State<AiHeadWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bob;

  // How far the head moves vertically, in logical pixels.
  static const double _bobAmplitude = 8.0;
  // One full up-down cycle duration. Slow + continuous.
  static const Duration _period = Duration(milliseconds: 2400);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _period,
    )..repeat(reverse: true);
    // 0.0 -> 1.0 -> 0.0 over each period gives a smooth up-then-down motion.
    _bob = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 56,
      height: widget.size + 56,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (context, child) {
          // Map eased [0,1] to a vertical offset centered around 0:
          // 0   -> -_bobAmplitude (up)
          // 0.5 ->  0            (mid)
          // 1   -> +_bobAmplitude (down)
          final double dy = (_bob.value - 0.5) * 2 * _bobAmplitude;
          return Transform.translate(
            offset: Offset(0, dy),
            child: child,
          );
        },
        child: _HeadTurn(
          size: widget.size,
          child: _HeadArt(size: widget.size),
        ),
      ),
    );
  }
}

/// Wraps the head art and periodically turns it left/right, like a person
/// glancing around, then returns to center. Uses a pseudo-3D perspective
/// rotation (rotateY) plus a subtle tilt and horizontal drift so the motion
/// reads as a head turn rather than a flat slide.
class _HeadTurn extends StatefulWidget {
  final double size;
  final Widget child;
  const _HeadTurn({required this.size, required this.child});

  @override
  State<_HeadTurn> createState() => _HeadTurnState();
}

class _HeadTurnState extends State<_HeadTurn>
    with SingleTickerProviderStateMixin {
  // -1.0 (full left) .. 0.0 (center) .. 1.0 (full right)
  late final AnimationController _controller;
  final Random _rng = Random();
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: -1.0,
      upperBound: 1.0,
      value: 0.0,
    );
    _runLoop();
  }

  Future<void> _wait(int ms) async {
    if (_disposed) return;
    await Future.delayed(Duration(milliseconds: ms));
  }

  Future<void> _turnTo(
    double target, {
    required int ms,
    Curve curve = Curves.easeInOut,
  }) async {
    if (_disposed) return;
    try {
      await _controller.animateTo(
        target,
        duration: Duration(milliseconds: ms),
        curve: curve,
      );
    } catch (_) {
      // Controller was disposed mid-animation; ignore.
    }
  }

  Future<void> _runLoop() async {
    while (!_disposed) {
      // Rest roughly centered for a while before the next glance.
      await _wait(1800 + _rng.nextInt(3200)); // 1.8s - 5.0s
      if (_disposed) return;

      // Pick a side and how far to turn.
      final double magnitude = 0.45 + _rng.nextDouble() * 0.55; // 0.45..1.0
      final double target = (_rng.nextBool() ? 1.0 : -1.0) * magnitude;
      await _turnTo(target, ms: 500 + _rng.nextInt(450));
      if (_disposed) return;

      // Hold the gaze briefly, like actually looking at something.
      await _wait(400 + _rng.nextInt(900));
      if (_disposed) return;

      // Occasionally glance the other way before coming back.
      if (_rng.nextDouble() < 0.3) {
        final double other =
            -target.sign * (0.45 + _rng.nextDouble() * 0.55);
        await _turnTo(other, ms: 450 + _rng.nextInt(400));
        if (_disposed) return;
        await _wait(300 + _rng.nextInt(700));
        if (_disposed) return;
      }

      // Return to center.
      await _turnTo(0.0, ms: 500 + _rng.nextInt(500),
          curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double t = _controller.value; // -1..1
        const double maxAngle = 0.42; // ~24 degrees of "turn"
        const double maxTilt = 0.05; // subtle tilt into the turn
        final double dx = t * (widget.size * 0.035);
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0016) // perspective
          ..translate(dx)
          ..rotateY(t * maxAngle)
          ..rotateZ(t * maxTilt);
        return Transform(
          alignment: Alignment.center,
          transform: matrix,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _HeadArt extends StatelessWidget {
  final double size;
  const _HeadArt({required this.size});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // headHalo
        Container(
          width: size + 56,
          height: size + 56,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color.fromRGBO(40, 120, 255, 0.10), Colors.transparent],
              stops: [0.30, 0.75],
            ),
          ),
        ),
        // head
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.24, -0.32),
              colors: [
                Color.fromRGBO(22, 44, 90, 0.88),
                Color.fromRGBO(5, 10, 28, 0.95),
                Color.fromRGBO(1, 2, 8, 0.99),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
            boxShadow: const [
              BoxShadow(color: Color.fromRGBO(60, 190, 255, 0.6), blurRadius: 0, spreadRadius: 1.5),
              BoxShadow(color: Color.fromRGBO(40, 150, 255, 0.32), blurRadius: 20, spreadRadius: 5),
              BoxShadow(color: Color.fromRGBO(20, 80, 200, 0.18), blurRadius: 50, spreadRadius: 14),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // headInner
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment(-0.16, -0.40),
                    colors: [Color.fromRGBO(40, 90, 180, 0.2), Colors.transparent],
                    stops: [0.0, 0.65],
                  ),
                ),
              ),
              // headReflection
              Positioned(
                top: size * 0.14,
                left: size * 0.18,
                width: size * 0.38,
                height: size * 0.20,
                child: Transform.rotate(
                  angle: -0.314159, // -18deg
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color.fromRGBO(200, 230, 255, 0.28), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              // headRim
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color.fromRGBO(90, 210, 255, 0.25), width: 1),
                ),
              ),
              // eyes — wrapped in _BlinkingEyes so both blink together.
              _BlinkingEyes(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Eye(),
                    SizedBox(width: size * 0.22),
                    const _Eye(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.30, -0.40),
          colors: [Colors.white, Color.fromRGBO(220, 242, 255, 0.92)],
        ),
        boxShadow: [
          BoxShadow(color: Color.fromRGBO(200, 235, 255, 0.75), blurRadius: 6, spreadRadius: 2),
          BoxShadow(color: Color.fromRGBO(100, 180, 255, 0.3), blurRadius: 16, spreadRadius: 5),
        ],
      ),
    );
  }
}

/// Wraps the row of eyes and applies a synchronized, human-like blink:
/// randomized interval, occasional double-blink, asymmetric close/open,
/// variable depth and duration.
class _BlinkingEyes extends StatefulWidget {
  final Widget child;
  const _BlinkingEyes({required this.child});

  @override
  State<_BlinkingEyes> createState() => _BlinkingEyesState();
}

class _BlinkingEyesState extends State<_BlinkingEyes>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Random _rng = Random();

  // Last tick time (passed into the Ticker callback).
  Duration _lastElapsed = Duration.zero;

  // Current blink state.
  //   _phase: 0 = idle, 1 = closing, 2 = opening.
  int _phase = 0;
  Duration _phaseStart = Duration.zero;
  Duration _phaseDuration = Duration.zero;

  // Per-blink parameters, randomized each blink.
  double _depth = 1.0; // 0.55..1.0 — how fully the eye closes.
  double _closeFraction = 0.35; // share of total duration spent closing.
  double _openFraction = 0.65;
  Duration _totalDuration = Duration(milliseconds: 200);

  Duration _idleRemaining = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    _lastElapsed = elapsed;
    switch (_phase) {
      case 0: // idle — wait, then start a blink
        _idleRemaining -= Duration(milliseconds: 16);
        if (_idleRemaining <= Duration.zero) {
          _startBlink();
        }
        break;
      case 1: // closing
      case 2: // opening
        final phaseElapsed = elapsed - _phaseStart;
        if (phaseElapsed >= _phaseDuration) {
          _advancePhase(elapsed);
        }
        break;
    }
    // Drive the rebuild manually; Ticker triggers setState per frame.
    setState(() {});
  }

  void _startBlink() {
    // Randomize blink parameters for this blink.
    _depth = 0.55 + _rng.nextDouble() * 0.45; // 0.55 .. 1.00
    final int totalMs = 110 + _rng.nextInt(210); // 110 .. 320 ms
    _totalDuration = Duration(milliseconds: totalMs);
    // Asymmetric: closing is faster than opening, mostly.
    _closeFraction = 0.28 + _rng.nextDouble() * 0.14; // 0.28 .. 0.42
    _openFraction = 1.0 - _closeFraction;

    _phase = 1;
    _phaseStart = _lastElapsed;
    _phaseDuration = Duration(
      milliseconds: (_totalDuration.inMilliseconds * _closeFraction).round(),
    );
  }

  void _advancePhase(Duration elapsed) {
    if (_phase == 1) {
      // move from closing to opening
      _phase = 2;
      _phaseStart = elapsed;
      _phaseDuration = Duration(
        milliseconds: (_totalDuration.inMilliseconds * _openFraction).round(),
      );
    } else {
      // blink finished — decide what's next.
      _phase = 0;
      // ~12% chance of a quick double-blink.
      final bool doubleBlink = _rng.nextDouble() < 0.12;
      // Idle until next blink: 2.2..6.0 s normally, ~250 ms for double.
      final int idleMs = doubleBlink
          ? 220 + _rng.nextInt(160) // 220..380 ms
          : 2200 + _rng.nextInt(3800); // 2200..6000 ms
      _idleRemaining = Duration(milliseconds: idleMs);
    }
  }

  /// Returns the eyelid closure fraction for the current frame:
  /// 0 = fully open, 1 = fully closed (at this blink's depth).
  double _closure() {
    if (_phase == 0) return 0;
    final ms = _phaseDuration.inMilliseconds;
    if (ms <= 0) return 0;
    final startUs = _phaseStart.inMicroseconds;
    final lastUs = _lastElapsed.inMicroseconds;
    final phaseElapsed = ((lastUs - startUs) / 1000.0); // ms
    final t = (phaseElapsed / ms).clamp(0.0, 1.0);
    if (_phase == 1) {
      // closing — easeOut cubic (avoids dart:math pow on web).
      final inv = 1 - t;
      final eased = 1 - inv * inv * inv;
      return eased * _depth;
    } else {
      // opening — easeInOut cubic.
      final double eased;
      if (t < 0.5) {
        eased = 4 * t * t * t;
      } else {
        final u = -2 * t + 2;
        eased = 1 - (u * u * u) / 2;
      }
      return (1 - eased) * _depth;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final closure = _closure();
    return Transform.scale(
      scaleY: 1 - closure,
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          // Eyelid line — faint dark line drawn across each eye as it closes.
          // Scaled with closure so it appears as the lid comes down.
          Opacity(
            opacity: closure.clamp(0.0, 1.0),
            child: IgnorePointer(
              child: SizedBox(
                width: 8 + 22 + 8, // left eye + gap + right eye
                height: 1.4,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(120, 180, 255, 0.55),
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromRGBO(60, 150, 255, 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}