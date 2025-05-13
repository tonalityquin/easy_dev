import 'package:flutter/material.dart';

class HqBoard extends StatefulWidget {
  const HqBoard({super.key});

  @override
  State<HqBoard> createState() => _HqBoardState();
}

class _HqBoardState extends State<HqBoard> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'hq 보드 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
