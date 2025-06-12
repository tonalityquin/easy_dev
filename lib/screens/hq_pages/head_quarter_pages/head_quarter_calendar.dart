import 'package:flutter/material.dart';

class HeadQuarterCalendar extends StatefulWidget {
  const HeadQuarterCalendar({super.key});

  @override
  State<HeadQuarterCalendar> createState() => _HeadQuarterCalendarState();
}

class _HeadQuarterCalendarState extends State<HeadQuarterCalendar> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'hq 캘린더 준비중',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
