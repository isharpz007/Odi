import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
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
              color: isUser
                  ? const Color.fromRGBO(90, 205, 255, 0.7)
                  : const Color.fromRGBO(70, 190, 255, 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color.fromRGBO(30, 120, 255, 0.18),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Text(
            message.text,
            style: const TextStyle(
              color: Color.fromRGBO(200, 222, 245, 0.92),
              fontSize: 15,
              height: 1.35,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}
