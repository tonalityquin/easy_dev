import 'package:flutter/material.dart';
import 'screens/go_to_work.dart';
import 'screens/headquarter_page.dart';
import 'screens/login/login_page.dart';
import 'screens/type_page.dart';
import 'screens/secondary_pages/office_mode_pages/location_management.dart';

/// 라우트 경로 상수 정의
class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const typePage = '/type_page';
  static const locationManagement = '/location_management';
  static const headquarterPage = '/headquarter_page'; // ✅ 추가
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.login: (context) => const LoginPage(),
  AppRoutes.home: (context) => const GoToWork(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.locationManagement: (context) => const LocationManagement(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(), // ✅ 추가
};
