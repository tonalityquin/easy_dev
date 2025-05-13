import 'package:flutter/material.dart';
import '../../widgets/navigation/top_navigation.dart';

class Headquarter extends StatefulWidget {
  const Headquarter({super.key});

  @override
  State<Headquarter> createState() => _HeadquarterState();
}

class _HeadquarterState extends State<Headquarter> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            '📊 Headquarter 콘텐츠 준비 중',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
  }
}
