import 'package:flutter/material.dart';

class TodoCalendar extends StatefulWidget {
  const TodoCalendar({super.key});

  @override
  State<TodoCalendar> createState() => _TodoCalendarState();
}

class _TodoCalendarState extends State<TodoCalendar> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '투두 캘린더 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
