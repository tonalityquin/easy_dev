import 'package:flutter/material.dart';

class StatisticalCalendar extends StatefulWidget {
  const StatisticalCalendar({super.key});

  @override
  State<StatisticalCalendar> createState() => _StatisticalCalendarState();
}

class _StatisticalCalendarState extends State<StatisticalCalendar> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '통계 달력 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
