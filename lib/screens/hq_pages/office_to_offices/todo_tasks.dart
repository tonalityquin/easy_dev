import 'package:flutter/material.dart';

class TodoTasks extends StatefulWidget {
  const TodoTasks({super.key});

  @override
  State<TodoTasks> createState() => _TodoTasksState();
}

class _TodoTasksState extends State<TodoTasks> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '투두 테스크 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
