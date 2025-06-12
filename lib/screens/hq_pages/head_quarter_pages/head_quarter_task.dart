import 'package:flutter/material.dart';

class HeadQuarterTask extends StatefulWidget {
  const HeadQuarterTask({super.key});

  @override
  State<HeadQuarterTask> createState() => _HeadQuarterTaskState();
}

class _HeadQuarterTaskState extends State<HeadQuarterTask> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'hq 테스크 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
