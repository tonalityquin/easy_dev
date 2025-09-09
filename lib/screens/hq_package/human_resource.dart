import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../repositories/user_repo_services/user_read_service.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'human_resource_package/break_calendar.dart';
import 'human_resource_package/attendance_calendar.dart';

class HumanResource extends StatefulWidget {
  const HumanResource({super.key});

  @override
  State<HumanResource> createState() => _HumanResourceState();
}

class _HumanResourceState extends State<HumanResource> {
  int _selectedIndex = 0; // 0: ATT, 1: Brk
  String? _selectedArea;
  bool _isLoading = true;

  // ✅ 서비스/구독 핸들
  final UserReadService _userReadService = UserReadService();
  StreamSubscription<List<dynamic>>? _userSubscription;

  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? 'belivus';
    _subscribeToUsers(area);
    setState(() {
      _selectedArea = area;
      _isLoading = false;
    });
  }

  void _subscribeToUsers(String area) {
    _userSubscription?.cancel();
    _userSubscription =
        _userReadService.watchUsersBySelectedArea(area).listen((users) {
          if (!mounted) return;
          // 필요 시 users로 UI 업데이트 로직 추가
        }, onError: (e, st) {
          // 에러 처리 필요 시 추가
        });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _selectedArea == null) {
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
        // ✅ 2개 탭만: 0=ATT, 1=Brk
        body: _selectedIndex == 0 ? AttendanceCalendar() : BreakCalendar(),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          currentIndex: _selectedIndex,
          icons: const [
            Icons.how_to_reg,       // ATT
            Icons.self_improvement, // Brk
          ],
          labels: const [
            'ATT',
            'Brk',
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
