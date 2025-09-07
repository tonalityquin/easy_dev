import 'package:flutter/material.dart';
import 'screens/commute_outside_package/commute_outside_screen.dart';
import 'screens/commute_package/commute_screen.dart';
import 'screens/headquarter_page.dart';
import 'screens/login_package/login_screen.dart';
import 'screens/tablet_page.dart';
import 'screens/type_page.dart';
import 'screens/login_selector_page.dart';

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
};
