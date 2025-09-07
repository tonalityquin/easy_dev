import 'package:flutter/material.dart';
import 'screens/commute_outside_package/commute_outside_screen.dart';
import 'screens/commute_package/commute_screen.dart';
import 'screens/headquarter_page.dart';
import 'screens/login_package/login_screen.dart';
import 'screens/tablet_page.dart';
import 'screens/type_page.dart';
import 'screens/login_selector_page.dart';

// ▼ 추가된 페이지들 (LoginSelectorPage와 같은 경로)
import 'screens/faq_page.dart';
import 'screens/parking_page.dart';

// ▼ 새로 만든 본사/관리 임시 페이지
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

  // ▼ 추가
  static const faq = '/faq';
  static const parking = '/parking';

  // ▼ 새 임시 라우트 (본사/관리 전용)
  static const communityStub = '/community_stub';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.selector: (context) => const LoginSelectorPage(),
  AppRoutes.serviceLogin: (context) => const LoginScreen(),
  AppRoutes.tabletLogin: (context) => const LoginScreen(mode: 'tablet'),
  AppRoutes.outsideLogin: (context) => const LoginScreen(mode: 'outside'),
  AppRoutes.commute: (context) => const CommuteScreen(),
  AppRoutes.commuteShortcut: (context) => const CommuteOutsideScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.tablet: (context) => const TabletPage(),

  // ▼ 추가
  AppRoutes.faq: (context) => const FaqPage(),
  AppRoutes.parking: (context) => const ParkingPage(),

  // ▼ 본사/관리 임시 페이지
  AppRoutes.communityStub: (context) => const CommunityStubPage(),
};
