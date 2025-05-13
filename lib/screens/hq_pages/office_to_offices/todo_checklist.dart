import 'package:flutter/material.dart';

class TodoChecklist extends StatefulWidget {
  const TodoChecklist({super.key});

  @override
  State<TodoChecklist> createState() => _TodoChecklistState();
}

class _TodoChecklistState extends State<TodoChecklist> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '투두 체크리스트 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
