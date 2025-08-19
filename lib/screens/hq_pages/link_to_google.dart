import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../type_pages/commons/dashboard_bottom_sheet/dash_board_page.dart';
import 'link_to_google_pages/cooperation_calendar.dart';
import 'link_to_google_pages/completed_event_page.dart';

final Map<String, String> calendarMap = {
  'belivus': '057a6dc84afa3ba3a28ef0f21f8c298100290f4192bcca55a55a83097d56d7fe@group.calendar.google.com',
  'pelican': '4ad4d982312d0b885144406cf7197d536ae7dfc36b52736c6bce726bec19c562@group.calendar.google.com',
};

class LinkToGoogle extends StatefulWidget {
  const LinkToGoogle({super.key});

  @override
  State<LinkToGoogle> createState() => _LinkToGoogleState();
}

class _LinkToGoogleState extends State<LinkToGoogle> {
  int _selectedIndex = 1;
  String? _selectedArea;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? 'belivus';
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

    final calendarId = calendarMap[_selectedArea] ?? calendarMap['belivus']!;

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
            ? CooperationCalendar(calendarId: calendarId)
            : _selectedIndex == 1
                ? const DashBoardPage()
                : _selectedIndex == 2
                    ? CompletedEventPage(calendarId: calendarId)
                    : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          currentIndex: _selectedIndex,
          icons: const [
            Icons.calendar_month,
            Icons.dashboard, // ✅ DashBoard 아이콘으로 변경
            Icons.task,
          ],
          labels: const [
            'Calendar',
            'DashBoard',
            'Done',
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
