// lib/routes.dart
import 'package:easydev/screens/dev_stub_page.dart';
import 'package:easydev/screens/head_stub_page.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/commute_package/commute_inside_screen.dart';
import 'screens/dev_package/dev_calendar_page.dart';
import 'screens/head_package/company_calendar_page.dart';
import 'screens/head_package/labor_guide_page.dart';
import 'screens/headquarter_page.dart';
import 'screens/login_package/login_screen.dart';
import 'screens/tablet_package/tablet_page.dart';
import 'screens/type_page.dart';
import 'selector_hubs_page.dart';

import 'screens/faq_page.dart';
import 'screens/parking_page.dart';

import 'screens/community_stub_page.dart';

// ▼ 신규 페이지 import
import 'screens/head_package/timesheet_page.dart';

class AppRoutes {
  static const selector = '/selector';
  static const serviceLogin = '/service_login';
  static const tabletLogin = '/tablet_login';
  static const outsideLogin = '/outside_login';
  static const commute = '/commute';
  static const commuteShortcut = '/commute_shortcut';
  static const headquarterPage = '/headquarter_page';
  static const typePage = '/type_page';
  static const tablet = '/tablet_page';
  static const faq = '/faq';
  static const parking = '/parking';
  static const communityStub = '/community_stub';
  static const headStub = '/head_stub';
  static const devStub = '/dev_stub';

  // ▼ 기존
  static const companyCalendar = '/company_calendar';
  static const devCalendar = '/dev_calendar';
  static const laborGuide = '/labor_guide';

  // ▼ 신규 라우트
  static const attendanceSheet = '/attendance_sheet';
  static const breakSheet = '/break_sheet';
}

/// ============================
/// 간단 라우트 가드: dev_auth + dev_auth_until 검사
/// ============================
const _prefsKeyDevAuth = 'dev_auth';
const _prefsKeyDevAuthUntil = 'dev_auth_until';

Future<bool> _isDevAuthorized() async {
  final prefs = await SharedPreferences.getInstance();
  final ok = prefs.getBool(_prefsKeyDevAuth) ?? false;
  final until = prefs.getInt(_prefsKeyDevAuthUntil);
  final alive = ok && until != null && DateTime.now().millisecondsSinceEpoch < until;
  if (!alive) {
    // 만료/미인증이면 정리(선택)
    await prefs.remove(_prefsKeyDevAuth);
    await prefs.remove(_prefsKeyDevAuthUntil);
  }
  return alive;
}

class _DevAuthGate extends StatelessWidget {
  const _DevAuthGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isDevAuthorized(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data == true) return child;
        return const _NotAuthorizedScreen();
      },
    );
  }
}

class _NotAuthorizedScreen extends StatelessWidget {
  const _NotAuthorizedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('권한 필요')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              const Text(
                '개발자 인증이 필요합니다.\n허브 화면에서 하단 펠리컨을 눌러 개발 코드를 입력하세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.selector),
                icon: const Icon(Icons.home),
                label: const Text('허브로 이동'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.selector: (context) => const SelectorHubsPage(),
  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.outsideLogin: (context) => const LoginScreen(mode: 'outside'),
  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),

  // ✅ 개발자 전용(또는 인증 필요) 라우트는 Gate로 감싼다
  AppRoutes.parking: (context) => const _DevAuthGate(child: ParkingPage()),
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const _DevAuthGate(child: DevStubPage()),

  // ▼ 기존 페이지
  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),
  AppRoutes.laborGuide: (context) => const LaborGuidePage(),

  // ▼ 신규 페이지 매핑
  AppRoutes.attendanceSheet: (context) =>
  const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) =>
  const TimesheetPage(initialTab: TimesheetTab.breakTime),
};
