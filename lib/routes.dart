// lib/routes.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easydev/screens/dev_stub_page.dart';
import 'package:easydev/screens/head_stub_page.dart';

import 'screens/commute_package/commute_outside_screen.dart';
import 'screens/commute_package/commute_inside_screen.dart';

import 'screens/dev_package/dev_calendar_page.dart';
import 'screens/dev_package/dev_calendar_package/calendar_model.dart' as devcal;
import 'screens/dev_package/dev_calendar_package/google_calendar_service.dart'
as devsvc;

import 'screens/head_package/company_calendar_page.dart';
import 'screens/head_package/calendar_package/calendar_model.dart' as headcal;
import 'screens/head_package/calendar_package/google_calendar_service.dart'
as headsvc;

import 'screens/head_package/labor_guide_page.dart';
import 'screens/headquarter_page.dart';
import 'screens/login_package/login_screen.dart';
import 'screens/tablet_package/tablet_page.dart';
import 'screens/type_page.dart';
import 'selector_hubs_page.dart';

import 'screens/faq_page.dart';
import 'screens/parking_page.dart';

import 'screens/community_stub_page.dart';

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

  // ▼ 신규 라우트
  static const companyCalendar = '/company_calendar';
  static const devCalendar = '/dev_calendar';
  static const laborGuide = '/labor_guide';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.selector: (context) => const SelectorHubsPage(),
  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.outsideLogin: (context) => const LoginScreen(mode: 'outside'),
  AppRoutes.commute: (context) => const CommuteInsideScreen(),
  AppRoutes.commuteShortcut: (context) => const CommuteOutsideScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),
  AppRoutes.faq: (context) => const FaqPage(),
  AppRoutes.parking: (context) => const ParkingPage(),
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
  AppRoutes.headStub: (context) => const HeadStubPage(),
  AppRoutes.devStub: (context) => const DevStubPage(),

  // ▼ 신규 페이지 매핑 (각 페이지별 알맞은 Provider 주입)
  AppRoutes.companyCalendar: (context) =>
      ChangeNotifierProvider<headcal.CalendarModel>(
        create: (_) => headcal.CalendarModel(headsvc.GoogleCalendarService()),
        child: const CompanyCalendarPage(),
      ),
  AppRoutes.devCalendar: (context) =>
      ChangeNotifierProvider<devcal.CalendarModel>(
        create: (_) => devcal.CalendarModel(devsvc.GoogleCalendarService()),
        child: const DevCalendarPage(),
      ),
  AppRoutes.laborGuide: (context) => const LaborGuidePage(),
};
