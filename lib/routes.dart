// lib/routes.dart
// 오프라인 모드용 라우팅 테이블
// - SharedPreferences 기반 DevAuthGate 제거
// - OfflineLoginScreen 성공 시 OfflineCommuteInsideScreen으로 이동하도록 연결

import 'package:flutter/material.dart';

// ▼ 오프라인 패키지
import 'package:easydev/offlines/commute_package/offline_commute_inside_screen.dart';
import 'package:easydev/offlines/login_package/offline_login_screen.dart';

// ▼ 일반 화면들
import 'package:easydev/screens/dev_stub_page.dart';
import 'package:easydev/screens/head_stub_page.dart';
import 'package:easydev/screens/headquarter_page.dart';
import 'package:easydev/screens/login_package/login_screen.dart';
import 'package:easydev/screens/type_page.dart';
import 'package:easydev/screens/tablet_package/tablet_page.dart';
import 'package:easydev/screens/faq_page.dart';
import 'package:easydev/screens/community_stub_page.dart';

import 'screens/commute_package/commute_inside_screen.dart';
import 'screens/dev_package/dev_calendar_page.dart';
import 'screens/head_package/company_calendar_page.dart';
import 'screens/head_package/labor_guide_page.dart';
import 'selector_hubs_page.dart';

// ▼ 신규 페이지 import
import 'screens/head_package/timesheet_page.dart';

class AppRoutes {
  static const selector = '/selector';
  static const serviceLogin = '/service_login';
  static const tabletLogin = '/tablet_login';

  // ✅ 오프라인 전용
  static const offlineLogin = '/offline_login';
  static const offlineCommute = '/offline_commute';

  static const commute = '/commute';
  static const headquarterPage = '/headquarter_page';
  static const typePage = '/type_page';
  static const tablet = '/tablet_page';
  static const faq = '/faq';

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

// =====================================================
// 오프라인 모드: DevAuthGate/SharedPreferences 의존 제거 버전
// =====================================================
//
// - OfflineLoginScreen에서 SQLite 세션 존재 시 자동으로 onLoginSucceeded 호출.
// - 오프라인 로그인 성공 시, '/offline_commute'로 이동(아래 routes에서 콜백 처리).
// - 필요 시, 앱의 초기 라우트를 '/offline_login'로 두거나
//   별도 '/offline_gate' 라우트에 OfflineEntryGate를 연결해도 됩니다.
//

final Map<String, WidgetBuilder> appRoutes = {
  // 허브(셀렉터)
  AppRoutes.selector: (context) => const SelectorHubsPage(),

  // 서비스/태블릿 로그인(온라인용 기존 화면: 유지)
  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),

  // ✅ 오프라인 로그인 → 성공 시 오프라인 출퇴근으로 이동
  AppRoutes.offlineLogin: (context) => OfflineLoginScreen(
    onLoginSucceeded: () =>
        Navigator.of(context).pushReplacementNamed(AppRoutes.offlineCommute),
  ),

  // 출퇴근(온라인/오프라인)
  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.offlineCommute: (context) => const OfflineCommuteInsideScreen(),

  // 기타 페이지들
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),

  // 스텁들(오프라인 모드에서는 권한 게이트 제거)
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  // 기존 페이지
  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),
  AppRoutes.laborGuide: (context) => const LaborGuidePage(),

  // 신규 타임시트 페이지
  AppRoutes.attendanceSheet: (context) =>
  const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) =>
  const TimesheetPage(initialTab: TimesheetTab.breakTime),
};

/* ────────────────────────────────────────────────────────────────────────────
※ 선택사항: 오프라인 진입 게이트 라우트를 쓰고 싶다면 아래를 추가하세요.
import 'package:easydev/offlines/offline_entry_gate.dart';

... routes 내에:
'/offline_gate': (context) => const OfflineEntryGate(
  offlineHomeRoute: AppRoutes.offlineCommute,
  loginRoute: AppRoutes.offlineLogin,
),

그리고 MaterialApp.initialRoute를 '/offline_gate'로 지정하면,
세션 유무에 따라 자동 분기됩니다.
──────────────────────────────────────────────────────────────────────────── */
