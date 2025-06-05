import 'package:flutter/material.dart';
import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'office_to_offices/todo_calendar.dart';
import 'office_to_offices/todo_checklist.dart';
import 'office_to_offices/todo_task_screen.dart';

class OfficeToOffice extends StatefulWidget {
  const OfficeToOffice({super.key});

  @override
  State<OfficeToOffice> createState() => _OfficeToOfficeState();
}

class _OfficeToOfficeState extends State<OfficeToOffice> {
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
            ? const TodoCalendar()
            : _selectedIndex == 1
            ? const TodoTaskScreen() // ✅ 새로운 탭 연결
            : _selectedIndex == 2
            ? const TodoChecklist() // ✅ 새로운 탭 연결
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
            'ToDo Calendar',
            'ToDo Tasks',
            'Todo Checklist',
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
