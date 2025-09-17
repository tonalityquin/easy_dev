import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../widgets/navigation/navigation_hq_mini.dart';
import '../../repositories/user_repo_services/user_read_service.dart';
import '../../widgets/navigation/top_navigation.dart';
import 'human_resource_package/break_calendar.dart';
import 'human_resource_package/attendance_calendar.dart';

/// Deep Blue Palette
class _Palette {
  static const base  = Color(0xFF0D47A1); // primary
  static const dark  = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg    = Colors.white;      // 전경(아이콘/텍스트)
}

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
    final baseTheme = Theme.of(context);

    if (_isLoading || _selectedArea == null) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: const AlwaysStoppedAnimation<Color>(_Palette.base),
              backgroundColor: _Palette.light.withOpacity(.25),
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: _Palette.dark,
          surfaceTintColor: _Palette.light,
          elevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              color: _Palette.light.withOpacity(.25),
            ),
          ),
        ),
        // ✅ 2개 탭만: 0=ATT, 1=Brk
        body: _selectedIndex == 0 ? AttendanceCalendar() : BreakCalendar(),
        bottomNavigationBar: Theme(
          // ⬇️ HqMiniNavigation에 Deep Blue 팔레트 주입
          data: baseTheme.copyWith(
            colorScheme: baseTheme.colorScheme.copyWith(
              primary: _Palette.base,
              secondary: _Palette.light,
              onPrimary: _Palette.fg,
              onSurface: _Palette.dark,
              surfaceTint: _Palette.light,
            ),
            iconTheme: IconThemeData(color: _Palette.dark.withOpacity(.80)),
            textTheme: baseTheme.textTheme.apply(
              bodyColor: _Palette.dark,
              displayColor: _Palette.dark,
            ),
          ),
          child: HqMiniNavigation(
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
      ),
    );
  }
}
