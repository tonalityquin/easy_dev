import 'package:flutter/material.dart';

class HqChat extends StatefulWidget {
  const HqChat({super.key});

  @override
  State<HqChat> createState() => _HqChatState();
}

class _HqChatState extends State<HqChat> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'hq 챗 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
