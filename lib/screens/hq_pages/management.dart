import 'dart:async';
import 'package:flutter/material.dart';

import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'management_pages/field.dart';
import 'management_pages/statistics.dart';
import 'management_pages/issue.dart';

class Management extends StatefulWidget {
  const Management({super.key});

  @override
  State<Management> createState() => _ManagementState();
}

class _ManagementState extends State<Management> {
  int _selectedIndex = 0;

  final TextEditingController _controller = TextEditingController();

  StreamSubscription? _userSubscription;

  @override
  void dispose() {
    _userSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

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
        body: _selectedIndex == 0
            ? const Field()
            : _selectedIndex == 1
            ? const Issue()
            : _selectedIndex == 2
            ? const Statistics()
            : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.directions_walk,    // Field
            Icons.report_problem,     // Issue
            Icons.compare_arrows,     // InOut (입출차 통계)
          ],
          labels: const [
            'Field',
            'Issue',
            'InOut',
          ],
          onIconTapped: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }
}
