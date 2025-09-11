// lib/utils/app_navigator.dart
import 'package:flutter/material.dart';

class AppNavigator {
  AppNavigator._();

  /// 전역 네비게이터 키 (오버레이/시트/내비)
  static final key = GlobalKey<NavigatorState>();

  /// 전역 스캐폴드메신저 키 (스낵바/머터리얼배너)
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static NavigatorState? get nav => key.currentState;
  static BuildContext? get context => nav?.context;
  static ScaffoldMessengerState? get messenger => scaffoldMessengerKey.currentState;
}
