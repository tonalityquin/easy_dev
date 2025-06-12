import 'package:flutter/material.dart';

class WorkerBreakDocument extends StatelessWidget {
  const WorkerBreakDocument({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('근태 문서'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const Center(
        child: Text(
          '여기에 컨텐츠를 작성하세요.',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
