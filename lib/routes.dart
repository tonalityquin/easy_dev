import 'package:easydev/offlines/offline_type_page.dart';
import 'package:easydev/screens/triple_headquarter_page.dart';
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

import 'screens/double_headquarter_page.dart';
import 'screens/double_mode/commute_package/double_commute_in_screen.dart';
import 'screens/double_type_page.dart';
import 'screens/triple_type_page.dart';
import 'screens/service_mode/commute_package/commute_inside_screen.dart';
import 'screens/hubs_mode/dev_package/dev_calendar_page.dart';
import 'screens/hubs_mode/head_package/company_calendar_page.dart';
import 'screens/single_mode/single_inside_screen.dart';
import 'screens/triple_mode/commute_package/triple_commute_in_screen.dart';
import 'selector_hubs_page.dart';

// ▼ 신규 페이지 import
import 'screens/hubs_mode/head_package/timesheet_page.dart';

class AppRoutes {
  static const selector = '/selector';
  static const serviceLogin = '/service_login';
  static const tabletLogin = '/tablet_login';
  static const doubleLogin = '/double_login';
  static const singleLogin = '/single_login';
  static const tripleLogin = '/triple_login';

  // ✅ 마이너 로그인 (신규)
  static const minorLogin = '/minor_login';

  // ✅ 오프라인 전용
  static const offlineLogin = '/offline_login';
  static const offlineCommute = '/offline_commute';
  static const commute = '/commute';
  static const singleCommute = '/single_commute';
  static const doubleCommute = '/double_commute';
  static const tripleCommute = '/triple_commute';

  static const headquarterPage = '/headquarter_page';
  static const doubleHeadquarterPage = '/double_headquarter_page';
  static const tripleHeadquarterPage = '/triple_headquarter_page';
  static const typePage = '/type_page';
  static const doubleTypePage = '/double_type_page';
  static const tripleTypePage = '/triple_type_page';
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
  AppRoutes.singleLogin: (context) => const LoginScreen(mode: 'single'),
  AppRoutes.doubleLogin: (context) => const LoginScreen(mode: 'double'),
  AppRoutes.tripleLogin: (context) => const LoginScreen(mode: 'triple'),

  // ✅ 마이너 로그인: 현재는 LoginScreen(mode:'triple')을 재사용 (리다이렉트로 목적지 분기)
  AppRoutes.minorLogin: (context) => const LoginScreen(mode: 'triple'),

  // ✅ 오프라인 로그인 → 성공 시 오프라인 출퇴근으로 이동
  AppRoutes.offlineLogin: (context) => OfflineLoginScreen(
    onLoginSucceeded: () => Navigator.of(context).pushReplacementNamed(AppRoutes.offlineCommute),
  ),

  // 출퇴근(온라인/약식/오프라인)
  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.doubleCommute: (context) => const DoubleCommuteInScreen(),
  AppRoutes.singleCommute: (context) => const SingleInsideScreen(),
  AppRoutes.offlineCommute: (context) => const OfflineCommuteInsideScreen(),
  AppRoutes.tripleCommute: (context) => const TripleCommuteInScreen(),

  // 기타 페이지들
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.doubleHeadquarterPage: (context) => const DoubleHeadquarterPage(),
  AppRoutes.tripleHeadquarterPage: (context) => const TripleHeadquarterPage(),
  AppRoutes.doubleTypePage: (context) => const LiteTypePage(),
  AppRoutes.tripleTypePage: (context) => const TripleTypePage(),
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
