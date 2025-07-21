import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'link_to_google_pages/google_task.dart';
import 'link_to_google_pages/google_calendar.dart';

class LinkToGoogle extends StatefulWidget {
  const LinkToGoogle({super.key});

  @override
  State<LinkToGoogle> createState() => _LinkToGoogleState();
}

class _LinkToGoogleState extends State<LinkToGoogle> {
  int _selectedIndex = 0;
  String? _selectedArea;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? 'belivus'; // 기본값 지정
    setState(() {
      _selectedArea = area;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
            ? GoogleCalendar(selectedArea: _selectedArea!)
                : _selectedIndex == 1
                    ? TaskListFromCalendar(selectedArea: _selectedArea!)
                    : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.calendar_month,
            Icons.task,
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
