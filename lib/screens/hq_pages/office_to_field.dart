import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'office_to_fields/today_field.dart';
import 'office_to_fields/parallel_graph.dart';
import 'office_to_fields/statistical_calendar.dart';

class OfficeToField extends StatefulWidget {
  const OfficeToField({super.key});

  @override
  State<OfficeToField> createState() => _OfficeToFieldState();
}

class _OfficeToFieldState extends State<OfficeToField> {
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
            ? const TodayField()
            : _selectedIndex == 1
                ? const StatisticalCalendar() // ✅ 새로운 탭 연결
                : _selectedIndex == 2
                    ? const ParallelGraph() // ✅ 새로운 탭 연결
                    : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.today,
            Icons.input,
            Icons.auto_graph,
          ],
          labels: const [
            'Today Field',
            'Statistical Calendar',
            'Parallel graph',
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
