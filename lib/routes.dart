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
import 'screens/minor_headquarter_page.dart';
import 'screens/minor_mode/commute_package/minor_commute_in_screen.dart';
import 'screens/minor_type_page.dart';
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
  static const minorLogin = '/minor_login';

  static const offlineLogin = '/offline_login';
  static const offlineCommute = '/offline_commute';

  static const commute = '/commute';
  static const singleCommute = '/single_commute';
  static const doubleCommute = '/double_commute';
  static const tripleCommute = '/triple_commute';
  static const minorCommute = '/minor_commute';

  static const headquarterPage = '/headquarter_page';
  static const doubleHeadquarterPage = '/double_headquarter_page';
  static const tripleHeadquarterPage = '/triple_headquarter_page';
  static const minorHeadquarterPage = '/minor_headquarter_page';

  static const typePage = '/type_page';
  static const doubleTypePage = '/double_type_page';
  static const tripleTypePage = '/triple_type_page';
  static const minorTypePage = '/minor_type_page';

  static const offlineTypePage = '/offline_type_page';

  static const tablet = '/tablet_page';
  static const faq = '/faq';

  static const communityStub = '/community_stub';
  static const headStub = '/head_stub';
  static const devStub = '/dev_stub';

  static const companyCalendar = '/company_calendar';
  static const devCalendar = '/dev_calendar';
  static const laborGuide = '/labor_guide';

  static const attendanceSheet = '/attendance_sheet';
  static const breakSheet = '/break_sheet';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.selector: (context) => const SelectorHubsPage(),

  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.singleLogin: (context) => const LoginScreen(mode: 'single'),
  AppRoutes.doubleLogin: (context) => const LoginScreen(mode: 'double'),
  AppRoutes.tripleLogin: (context) => const LoginScreen(mode: 'triple'),

  // ✅ minor 로그인
  AppRoutes.minorLogin: (context) => const LoginScreen(mode: 'minor'),

  AppRoutes.offlineLogin: (context) => OfflineLoginScreen(
    onLoginSucceeded: () => Navigator.of(context).pushReplacementNamed(AppRoutes.offlineCommute),
  ),

  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.doubleCommute: (context) => const DoubleCommuteInScreen(),
  AppRoutes.singleCommute: (context) => const SingleInsideScreen(),
  AppRoutes.offlineCommute: (context) => const OfflineCommuteInsideScreen(),
  AppRoutes.tripleCommute: (context) => const TripleCommuteInScreen(),

  // ✅ minor 출퇴근(임시: triple 출퇴근 재사용)
  AppRoutes.minorCommute: (context) => const MinorCommuteInScreen(),

  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.doubleHeadquarterPage: (context) => const DoubleHeadquarterPage(),
  AppRoutes.tripleHeadquarterPage: (context) => const TripleHeadquarterPage(),

  // ✅ minor 본사(임시: triple 본사 재사용)
  AppRoutes.minorHeadquarterPage: (context) => const MinorHeadquarterPage(),

  AppRoutes.doubleTypePage: (context) => const LiteTypePage(),
  AppRoutes.tripleTypePage: (context) => const TripleTypePage(),

  // ✅ minor 타입(임시: triple 타입 재사용)
  AppRoutes.minorTypePage: (context) => const MinorTypePage(),

  AppRoutes.offlineTypePage: (context) => const OfflineTypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),

  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),

  AppRoutes.attendanceSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.breakTime),
};
