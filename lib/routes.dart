import 'package:flutter/material.dart';
import 'screens/into_work/into_work_screen.dart';
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
}

final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.login: (context) => const LoginScreen(),
  AppRoutes.home: (context) => const IntoWorkScreen(),
  AppRoutes.headquarterPage: (context) => const HeadquarterPage(),
  AppRoutes.typePage: (context) => const TypePage(),
  AppRoutes.locationManagement: (context) => const LocationManagement(),
};
