import 'dart:ui';
import 'package:flutter/material.dart';
import 'send_button.dart';

class ChatInput extends StatelessWidget {
  final TextEditingController? controller;
  final VoidCallback? onSend;
  const ChatInput({super.key, this.controller, this.onSend});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // inputGlow
        Positioned(
          top: -12,
          left: -12,
          right: -12,
          bottom: -12,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(60),
              gradient: const RadialGradient(
                colors: [Color.fromRGBO(40, 130, 255, 0.12), Colors.transparent],
                stops: [0.0, 0.70],
              ),
            ),
          ),
        ),
        // inputPill
        ClipRRect(
          borderRadius: BorderRadius.circular(60),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
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
                border: Border.all(color: const Color.fromRGBO(55, 180, 255, 0.48), width: 1),
                boxShadow: const [
                  BoxShadow(color: Color.fromRGBO(30, 120, 255, 0.2), blurRadius: 18, spreadRadius: 4),
                  BoxShadow(color: Color.fromRGBO(15, 60, 180, 0.1), blurRadius: 40, spreadRadius: 10),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      style: const TextStyle(
                        color: Color.fromRGBO(180, 210, 240, 0.6),
                        fontSize: 15,
                        letterSpacing: 0.15,
                      ),
                      cursorColor: const Color.fromRGBO(80, 180, 255, 0.8),
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        hintStyle: TextStyle(color: Color.fromRGBO(180, 210, 240, 0.4)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SendButton(onPressed: onSend),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}