import 'package:flutter/material.dart';
import 'screens/go_to_work.dart';
import 'screens/login_page.dart';
import 'screens/type_page.dart';
import 'screens/secondary_pages/office_mode_pages/location_management.dart';

// 라우팅 정보
final Map<String, WidgetBuilder> appRoutes = {
  '/login': (context) => const LoginPage(),
  '/home': (context) => const GoToWork(),
  '/type_page': (context) => const TypePage(),
  '/location_management': (context) => const LocationManagement(), // LocationManagement 추가 가능
};

/// ## Improvement
/// 1. 다이나믹 라우팅 적용 고려s
/// ID에 따라 다른 페이지를 렌더링
