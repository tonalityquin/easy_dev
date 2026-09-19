import 'package:flutter/material.dart';

class AppNavigatorObserver extends NavigatorObserver {
  String? currentRoute;

  void _setCurrent(Route<dynamic>? route) {
    currentRoute = route?.settings.name;
    debugPrint(
      '[APP_NAVIGATOR][${DateTime.now().toIso8601String()}] currentRoute=${currentRoute ?? '-'}',
    );
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _setCurrent(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(previousRoute);
  }
}

class AppNavigator {
  AppNavigator._();

  static final key = GlobalKey<NavigatorState>();
  static final observer = AppNavigatorObserver();
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  static NavigatorState? get nav => key.currentState;
  static BuildContext? get context => nav?.context;
  static ScaffoldMessengerState? get messenger => scaffoldMessengerKey.currentState;
  static String? get currentRoute => observer.currentRoute;
}
