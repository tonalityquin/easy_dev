import 'package:flutter/material.dart';

class ParallelGraph extends StatefulWidget {
  const ParallelGraph({super.key});

  @override
  State<ParallelGraph> createState() => _ParallelGraphState();
}

class _ParallelGraphState extends State<ParallelGraph> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '비교 그래프 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
