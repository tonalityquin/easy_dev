// lib/routes.dart
import 'package:easydev/offlines/offline_type_page.dart';
import 'package:easydev/screens/normal_headquarter_page.dart';
import 'package:flutter/material.dart';

// ▼ 오프라인 패키지
import 'package:easydev/offlines/offline_commute_package/offline_commute_inside_screen.dart';
import 'package:easydev/offlines/offline_login_package/offline_login_screen.dart';

// ▼ 일반 화면들
import 'package:easydev/screens/hubs_mode/dev_stub_page.dart';
import 'package:easydev/screens/hubs_mode/head_stub_page.dart';
import 'package:easydev/screens/headquarter_page.dart';
import 'package:easydev/screens/hubs_mode/login_package/login_screen.dart';
import 'package:easydev/screens/type_page.dart';
import 'package:easydev/screens/tablet_mode/tablet_page.dart';
import 'package:easydev/screens/hubs_mode/faq_page.dart';
import 'package:easydev/screens/hubs_mode/community_stub_page.dart';

import 'screens/lite_headquarter_page.dart';
import 'screens/lite_mode/lite_commute_package/lite_commute_inside_screen.dart';
import 'screens/lite_type_page.dart';
import 'screens/normal_mode/normal_commute_package/normal_commute_inside_screen.dart';
import 'screens/normal_type_page.dart';
import 'screens/service_mode/commute_package/commute_inside_screen.dart';
import 'screens/hubs_mode/dev_package/dev_calendar_page.dart';
import 'screens/hubs_mode/head_package/company_calendar_page.dart';
import 'screens/support_mode/support_inside_screen.dart';
import 'selector_hubs_page.dart';

// ▼ 신규 페이지 import
import 'screens/hubs_mode/head_package/timesheet_page.dart';

class AppRoutes {
  static const selector = '/selector';
  static const serviceLogin = '/service_login';
  static const tabletLogin = '/tablet_login';
  static const liteLogin = '/lite_login';
  static const simpleLogin = '/simple_login';
  static const normalLogin = '/normal_login';

  // ✅ 오프라인 전용
  static const offlineLogin = '/offline_login';
  static const offlineCommute = '/offline_commute';
  static const commute = '/commute';
  static const simpleCommute = '/simple_commute';
  static const liteCommute = '/lite_commute';
  static const normalCommute = '/normal_commute';

  static const headquarterPage = '/headquarter_page';
  static const liteHeadquarterPage = '/lite_headquarter_page';
  static const normalHeadquarterPage = '/normal_headquarter_page';
  static const typePage = '/type_page';
  static const liteTypePage = '/lite_type_page';
  static const normalTypePage = '/normal_type_page';
  static const offlineTypePage = '/offline_type_page';

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

final Map<String, WidgetBuilder> appRoutes = {
  // 허브(셀렉터)
  AppRoutes.selector: (context) => const SelectorHubsPage(),

  // 서비스/태블릿 로그인(온라인용 기존 화면: 유지)
  AppRoutes.serviceLogin: (context) => const LoginScreen(), // mode 기본값 = 'service'
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.simpleLogin: (context) => const LoginScreen(mode: 'simple'),
  AppRoutes.liteLogin: (context) => const LoginScreen(mode: 'lite'),
  AppRoutes.normalLogin: (context) => const LoginScreen(mode: 'normal'),

  // ✅ 오프라인 로그인 → 성공 시 오프라인 출퇴근으로 이동
  AppRoutes.offlineLogin: (context) => OfflineLoginScreen(
        onLoginSucceeded: () => Navigator.of(context).pushReplacementNamed(AppRoutes.offlineCommute),
      ),

  // 출퇴근(온라인/약식/오프라인)
  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.liteCommute: (context) => const LiteCommuteInsideScreen(),
  AppRoutes.simpleCommute: (context) => const SupportInsideScreen(),
  AppRoutes.offlineCommute: (context) => const OfflineCommuteInsideScreen(),
  AppRoutes.normalCommute: (context) => const NormalCommuteInsideScreen(),

  // 기타 페이지들
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.liteHeadquarterPage: (context) => const LiteHeadquarterPage(),
  AppRoutes.normalHeadquarterPage: (context) => const NormalHeadquarterPage(),
  AppRoutes.liteTypePage: (context) => const LiteTypePage(),
  AppRoutes.normalTypePage: (context) => const NormalTypePage(),
  AppRoutes.offlineTypePage: (context) => const OfflineTypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),

  // 스텁들(오프라인 모드에서는 권한 게이트 제거)
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  // 기존 페이지
  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),

  // 신규 타임시트 페이지
  AppRoutes.attendanceSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.breakTime),
};
