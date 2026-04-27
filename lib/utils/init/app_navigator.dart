import 'package:flutter/material.dart';

class AppNavigator {
  AppNavigator._();

  static final key = GlobalKey<NavigatorState>();

  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static NavigatorState? get nav => key.currentState;

  static BuildContext? get context => nav?.context;

  static ScaffoldMessengerState? get messenger =>
      scaffoldMessengerKey.currentState;
}
