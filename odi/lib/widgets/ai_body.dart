import 'dart:ui';
import 'package:flutter/material.dart';

class AiBodyWidget extends StatelessWidget {
  final double size;
  final Widget child; // CenterControl, positioned like the original nested div

  const AiBodyWidget({super.key, required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // bodyGlow
          Positioned(
            top: -20,
            child: Container(
              width: size * 0.90,
              height: 200,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Color.fromRGBO(50, 130, 255, 0.16),
                    Color.fromRGBO(20, 70, 200, 0.07),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.55, 0.80],
                ),
              ),
            ),
          ),
          // body
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(0.0, -0.60),
                radius: 0.8,
                colors: [
                  Color.fromRGBO(110, 185, 255, 0.68),
                  Color.fromRGBO(55, 120, 235, 0.52),
                  Color.fromRGBO(18, 52, 150, 0.48),
                  Color.fromRGBO(4, 12, 45, 0.88),
                  Color.fromRGBO(0, 1, 8, 0.99),
                ],
                stops: [0.0, 0.18, 0.42, 0.68, 1.0],
              ),
              boxShadow: const [
                BoxShadow(color: Color.fromRGBO(70, 150, 255, 0.18), blurRadius: 60, spreadRadius: 8, offset: Offset(0, -16)),
                BoxShadow(color: Color.fromRGBO(25, 70, 190, 0.13), blurRadius: 100, spreadRadius: 25),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // bodyHighlight (CSS filter: blur(10px))
                Positioned(
                  top: 20,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      width: size * 0.55,
                      height: 100,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color.fromRGBO(200, 232, 255, 0.52),
                            Color.fromRGBO(140, 205, 255, 0.22),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // bodyHighlight2 (CSS filter: blur(5px))
                Positioned(
                  top: 6,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      width: size * 0.30,
                      height: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Color.fromRGBO(235, 248, 255, 0.68),
                            Color.fromRGBO(180, 225, 255, 0.28),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // bodySpecular (CSS filter: blur(4px)), offset left by 14%
                Positioned(
                  top: 34,
                  child: FractionalTranslation(
                    translation: const Offset(-0.14 / 0.22, 0), // shifts left by 14% of size relative to width
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                      child: Container(
                        width: size * 0.22,
                        height: 30,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Color.fromRGBO(255, 255, 255, 0.5),
                              Color.fromRGBO(225, 245, 255, 0.18),
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // bodyRim
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color.fromRGBO(60, 190, 255, 0.18), width: 1),
                  ),
                ),
                // center control, nested exactly like the original
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}