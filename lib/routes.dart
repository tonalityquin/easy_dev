import 'package:flutter/material.dart';
import 'screens/clock_in_pages/clock_in_work_screen.dart';
import 'screens/headquarter_page.dart';
import 'screens/logins/login_screen.dart';
import 'screens/type_page.dart';
import 'screens/secondary_pages/field_mode_pages/location_management.dart';

class AppRoutes {
  static const login = '/login';
  static const home = '/home';
  static const typePage = '/type_page';
  static const locationManagement = '/location_management';
  static const headquarterPage = '/headquarter_page';
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.login: (context) => const LoginScreen(),
  AppRoutes.home: (context) => const ClockInWorkScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.locationManagement: (context) => const LocationManagement(),
};
