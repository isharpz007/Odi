import 'package:flutter/material.dart';

class SendButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const SendButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-0.24, -0.40),
            colors: [
              Color.fromRGBO(18, 38, 80, 0.95),
              Color.fromRGBO(4, 8, 22, 0.98),
              Color.fromRGBO(1, 2, 8, 1),
            ],
            stops: [0.0, 0.60, 1.0],
          ),
          boxShadow: const [
            BoxShadow(color: Color.fromRGBO(60, 190, 255, 0.55), blurRadius: 0, spreadRadius: 1),
            BoxShadow(color: Color.fromRGBO(40, 160, 255, 0.3), blurRadius: 12, spreadRadius: 3),
            BoxShadow(color: Color.fromRGBO(20, 100, 220, 0.18), blurRadius: 32, spreadRadius: 8),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // sendBtnInner
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.24, -0.40),
                  colors: [Color.fromRGBO(32, 75, 165, 0.25), Colors.transparent],
                  stops: [0.0, 0.65],
                ),
              ),
            ),
            // sendBtnRim
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color.fromRGBO(90, 210, 255, 0.22), width: 1),
              ),
            ),
            // SendIcon
            SizedBox(
              width: 16,
              height: 16,
              child: CustomPaint(painter: _SendIconPainter()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.scale(scale);

    final paint = Paint()
      ..color = const Color.fromRGBO(140, 210, 255, 0.9)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}