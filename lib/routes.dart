// lib/routes.dart
import 'package:easydev/screens/dev_stub_page.dart';
import 'package:easydev/screens/head_stub_page.dart';
import 'package:flutter/material.dart';
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
  AppRoutes.parking: (context) => const ParkingPage(),
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  // ▼ 기존 페이지
  AppRoutes.companyCalendar: (context) => const CompanyCalendarPage(),
  AppRoutes.devCalendar: (context) => const DevCalendarPage(),
  AppRoutes.laborGuide: (context) => const LaborGuidePage(),

  // ▼ 신규 페이지 매핑
  AppRoutes.attendanceSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.attendance),
  AppRoutes.breakSheet: (context) => const TimesheetPage(initialTab: TimesheetTab.breakTime),
};
