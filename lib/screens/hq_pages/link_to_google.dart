import 'package:flutter/material.dart';
import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'head_quarter_pages/google_task.dart';
import 'head_quarter_pages/google_calendar.dart';

class LinkToGoogle extends StatefulWidget {
  const LinkToGoogle({super.key});

  @override
  State<LinkToGoogle> createState() => _LinkToGoogleState();
}

class _LinkToGoogleState extends State<LinkToGoogle> {
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
            ? const GoogleCalendar()
            : _selectedIndex == 1
                ? const GoogleTask()
                : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.input,
            Icons.today,
          ],
          labels: const [
            'Calendar',
            'Task',
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
