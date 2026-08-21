import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const OdiAIApp());
}

class OdiAIApp extends StatelessWidget {
  const OdiAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OdiAI',
      home: const TestConnectionScreen(),
    );
  }
}

class TestConnectionScreen extends StatefulWidget {
  const TestConnectionScreen({super.key});

  @override
  State<TestConnectionScreen> createState() =>
      _TestConnectionScreenState();
}

class _TestConnectionScreenState extends State<TestConnectionScreen> {
  String message = 'Not connected';

  Future<void> testBackend() async {
    try {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:8000/hello'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          message = data['message'];
        });
      } else {
        setState(() {
          message = 'Backend error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        message = 'Connection failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OdiAI Connection Test'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(message),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: testBackend,
              child: const Text('Test Backend'),
            ),
          ],
        ),
      ),
    );
  }
}