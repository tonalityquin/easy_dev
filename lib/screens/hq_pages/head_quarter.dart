import 'package:flutter/material.dart';
import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'head_quarter_pages/head_quarter_calendar.dart';
import 'head_quarter_pages/head_quarter_task.dart';

class HeadQuarter extends StatefulWidget {
  const HeadQuarter({super.key});

  @override
  State<HeadQuarter> createState() => _HeadQuarterState();
}

class _HeadQuarterState extends State<HeadQuarter> {
  int _selectedIndex = 0;

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
            ? const HeadQuarterTask()
            : _selectedIndex == 1
                ? const HeadQuarterCalendar()
                : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.today,
            Icons.input,
          ],
          labels: const [
            'Task',
            'Calendar',
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
