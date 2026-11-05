import 'package:flutter/material.dart';

class AppNavigatorObserver extends NavigatorObserver {
  String? currentRoute;
  ValueChanged<String?>? onRouteChanged;
  ValueChanged<String?>? onRouteSettled;

  final Map<Route<dynamic>, AnimationStatusListener> _settleListeners =
      <Route<dynamic>, AnimationStatusListener>{};
  final List<Route<dynamic>> _routeStack = <Route<dynamic>>[];
  final Set<TransitionRoute<dynamic>> _pendingOverlayRemovals =
      <TransitionRoute<dynamic>>{};
  final Set<VoidCallback> _routeChangeListeners = <VoidCallback>{};

  Route<dynamic>? get currentTopRoute =>
      _routeStack.isEmpty ? null : _routeStack.last;

  bool get hasPendingOverlayRemovals => _pendingOverlayRemovals.isNotEmpty;

  bool containsRoute(Route<dynamic> route) => _routeStack.contains(route);

  void addRouteChangeListener(VoidCallback listener) {
    _routeChangeListeners.add(listener);
  }

  void removeRouteChangeListener(VoidCallback listener) {
    _routeChangeListeners.remove(listener);
  }

  void _notifyRouteChangeListeners() {
    for (final listener in List<VoidCallback>.of(_routeChangeListeners)) {
      listener();
    }
  }

  void _trackOverlayRemoval(Route<dynamic> route) {
    if (route is! TransitionRoute<dynamic>) return;
    _pendingOverlayRemovals.add(route);
    route.completed.whenComplete(() {
      _pendingOverlayRemovals.remove(route);
      _notifyRouteChangeListeners();
    });
  }

  void _setCurrent(Route<dynamic>? route) {
    currentRoute = route?.settings.name;
    onRouteChanged?.call(currentRoute);
    debugPrint(
      '[APP_NAVIGATOR][${DateTime.now().toIso8601String()}] currentRoute=${currentRoute ?? '-'}',
    );
    _notifyRouteChangeListeners();
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
    _routeStack.remove(route);
    _routeStack.add(route);
    _setCurrent(currentTopRoute);
    _watchPushOrReplaceSettled(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStack.remove(route);
    _trackOverlayRemoval(route);
    final next = currentTopRoute;
    _setCurrent(next);
    _watchPopSettled(route, next);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _detachSettleListener(oldRoute);
    final index = oldRoute == null ? -1 : _routeStack.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routeStack.removeAt(index);
      } else {
        _routeStack[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routeStack.remove(newRoute);
      _routeStack.add(newRoute);
    }
    _setCurrent(currentTopRoute);
    if (newRoute != null) {
      _watchPushOrReplaceSettled(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _detachSettleListener(route);
    _routeStack.remove(route);
    _trackOverlayRemoval(route);
    final next = currentTopRoute;
    _setCurrent(next);
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _notifySettled(next),
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
