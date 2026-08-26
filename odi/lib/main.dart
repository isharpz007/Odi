import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';

void main() {
  runApp(const OdiAIApp());
}

class OdiAIApp extends StatelessWidget {
  const OdiAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OdiAI',
      debugShowCheckedModeBanner: false,
      home: const ChatScreen(),
    );
  }
}
