import 'package:flutter/material.dart';

class CenterControl extends StatelessWidget {
  final double size;
  final VoidCallback? onTap;
  const CenterControl({super.key, required this.size, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size + 36,
        height: size + 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // centerBtnHalo
            Container(
              width: size + 36,
              height: size + 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color.fromRGBO(40, 140, 255, 0.14), Colors.transparent],
                  stops: [0.30, 0.75],
                ),
              ),
            ),
            // centerBtn
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.24, -0.32),
                  colors: [
                    Color.fromRGBO(20, 42, 88, 0.9),
                    Color.fromRGBO(4, 8, 24, 0.96),
                    Color.fromRGBO(1, 2, 8, 1),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
                boxShadow: const [
                  BoxShadow(color: Color.fromRGBO(60, 190, 255, 0.62), blurRadius: 0, spreadRadius: 1.2),
                  BoxShadow(color: Color.fromRGBO(40, 150, 255, 0.32), blurRadius: 14, spreadRadius: 4),
                  BoxShadow(color: Color.fromRGBO(20, 80, 200, 0.16), blurRadius: 36, spreadRadius: 10),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // centerBtnInner
                  Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: Alignment(-0.20, -0.40),
                        colors: [Color.fromRGBO(35, 80, 170, 0.22), Colors.transparent],
                        stops: [0.0, 0.65],
                      ),
                    ),
                  ),
                  // centerBtnReflection
                  Positioned(
                    top: size * 0.14,
                    left: size * 0.18,
                    width: size * 0.36,
                    height: size * 0.18,
                    child: Transform.rotate(
                      angle: -0.314159,
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color.fromRGBO(200, 230, 255, 0.26), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // centerBtnRim
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color.fromRGBO(90, 210, 255, 0.22), width: 1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}