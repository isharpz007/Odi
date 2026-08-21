import 'package:flutter/material.dart';

class AiHeadWidget extends StatelessWidget {
  final double size;
  const AiHeadWidget({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 56,
      height: size + 56,
      child: Stack(
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
                // eyes
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Eye(),
                    SizedBox(width: size * 0.22),
                    const _Eye(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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