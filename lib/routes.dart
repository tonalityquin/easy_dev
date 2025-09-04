import 'package:flutter/material.dart';
import 'screens/clock_in_pages/clock_in_work_screen.dart';
import 'screens/headquarter_page.dart';
import 'screens/logins/login_screen.dart';
import 'screens/type_page.dart';
import 'screens/secondary_pages/office_mode_pages/location_management.dart';

class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const typePage = '/type_page';
  static const locationManagement = '/location_management';
  static const headquarterPage = '/headquarter_page';

  // ✅ 추가: 태블릿 전용 로그인 라우트
  static const loginTablet = '/login_tablet';
}

final Map<String, WidgetBuilder> appRoutes = {
  // 기본: 서비스 로그인
  AppRoutes.login: (context) => const LoginScreen(),

  // ✅ 추가: 같은 LoginScreen을 사용하되 tablet 모드로
  AppRoutes.loginTablet: (context) => const LoginScreen(mode: 'tablet'),

  AppRoutes.home: (context) => const ClockInWorkScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.locationManagement: (context) => const LocationManagement(),
};
