import 'package:flutter/material.dart';
import 'screens/type_page.dart'; // 메인 화면 (타입 선택 화면)
import 'screens/login_page.dart'; // 로그인 화면
import 'screens/secondary_pages/office_mode_pages/location_management.dart'; // LocationManagement 페이지

// 라우팅 정보
final Map<String, WidgetBuilder> appRoutes = {
  '/login': (context) => const LoginPage(),
  '/home': (context) => const TypePage(),
  '/location_management': (context) => const LocationManagement(), // LocationManagement 추가 가능
};

/// ## Improvement
/// 1. 다이나믹 라우팅 적용 고려
/// ID에 따라 다른 페이지를 렌더링
