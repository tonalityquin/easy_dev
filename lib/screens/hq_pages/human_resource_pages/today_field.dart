import 'package:flutter/material.dart';

class TodayField extends StatefulWidget {
  const TodayField({super.key});

  @override
  State<TodayField> createState() => _TodayFieldState();
}

class _TodayFieldState extends State<TodayField> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '공란',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
