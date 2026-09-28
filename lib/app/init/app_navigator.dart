import 'package:flutter/material.dart';

class AppNavigatorObserver extends NavigatorObserver {
  String? currentRoute;
  ValueChanged<String?>? onRouteChanged;
  ValueChanged<String?>? onRouteSettled;

  final Map<Route<dynamic>, AnimationStatusListener> _settleListeners =
      <Route<dynamic>, AnimationStatusListener>{};

  void _setCurrent(Route<dynamic>? route) {
    currentRoute = route?.settings.name;
    onRouteChanged?.call(currentRoute);
    debugPrint(
      '[APP_NAVIGATOR][${DateTime.now().toIso8601String()}] currentRoute=${currentRoute ?? '-'}',
    );
  }

  void _notifySettled(Route<dynamic>? route) {
    if (route == null || !route.isCurrent) return;
    currentRoute = route.settings.name;
    onRouteSettled?.call(currentRoute);
    debugPrint(
      '[APP_NAVIGATOR_SETTLED][${DateTime.now().toIso8601String()}] currentRoute=${currentRoute ?? '-'}',
    );
  }

  Animation<double>? _routeAnimation(Route<dynamic>? route) {
    if (route is TransitionRoute<dynamic>) {
      return route.animation;
    }
    return null;
  }

  void _watchPushOrReplaceSettled(Route<dynamic> route) {
    _detachSettleListener(route);
    final animation = _routeAnimation(route);
    if (animation == null || animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifySettled(route));
      return;
    }

    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      _settleListeners.remove(route);
      _notifySettled(route);
    };
    _settleListeners[route] = listener;
    animation.addStatusListener(listener);
  }

  void _watchPopSettled(
    Route<dynamic> poppedRoute,
    Route<dynamic>? previousRoute,
  ) {
    _detachSettleListener(poppedRoute);
    if (previousRoute == null) return;
    final animation = _routeAnimation(poppedRoute);
    if (animation == null || animation.status == AnimationStatus.dismissed) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _notifySettled(previousRoute),
      );
      return;
    }

    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(listener);
      _settleListeners.remove(poppedRoute);
      _notifySettled(previousRoute);
    };
    _settleListeners[poppedRoute] = listener;
    animation.addStatusListener(listener);
  }

  void _detachSettleListener(Route<dynamic>? route) {
    if (route == null) return;
    final listener = _settleListeners.remove(route);
    final animation = _routeAnimation(route);
    if (listener != null && animation != null) {
      animation.removeStatusListener(listener);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(route);
    _watchPushOrReplaceSettled(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setCurrent(previousRoute);
    _watchPopSettled(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _detachSettleListener(oldRoute);
    _setCurrent(newRoute);
    if (newRoute != null) {
      _watchPushOrReplaceSettled(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _detachSettleListener(route);
    _setCurrent(previousRoute);
    if (previousRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _notifySettled(previousRoute),
      );
    }
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
