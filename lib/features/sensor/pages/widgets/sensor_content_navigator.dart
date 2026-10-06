import 'package:flutter/material.dart';

import '../../applications/sensor_debug_trace.dart';
import 'sensor_detection_content.dart';

class SensorContentNavigator extends StatefulWidget {
  const SensorContentNavigator({
    super.key,
    required this.navigatorKey,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<SensorContentNavigator> createState() =>
      _SensorContentNavigatorState();
}

class _SensorContentNavigatorState extends State<SensorContentNavigator> {
  late final NavigatorObserver _observer;

  @override
  void initState() {
    super.initState();
    _observer = _SensorContentNavigatorObserver();
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'initialized',
    );
  }

  @override
  void dispose() {
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'disposed',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentMedia = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedSize = constraints.biggest;
        final contentSize = constrainedSize.width.isFinite &&
                constrainedSize.height.isFinite &&
                constrainedSize.width > 0 &&
                constrainedSize.height > 0
            ? constrainedSize
            : parentMedia.size;
        return ClipRect(
          child: MediaQuery(
            data: parentMedia.copyWith(
              size: contentSize,
            ),
            child: Navigator(
              key: widget.navigatorKey,
              observers: <NavigatorObserver>[
                _observer,
              ],
              onGenerateInitialRoutes: (navigator, initialRoute) {
                return <Route<dynamic>>[
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(
                      name: '/sensor_detection',
                    ),
                    builder: (_) => const SensorDetectionContent(),
                  ),
                ];
              },
              onGenerateRoute: (settings) {
                SensorDebugTrace.record(
                  'SensorContentNavigator',
                  'unknown_route_requested',
                  <String, Object?>{
                    'name': settings.name ?? '',
                  },
                );
                return MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => const SensorDetectionContent(),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SensorContentNavigatorObserver extends NavigatorObserver {
  String _routeName(Route<dynamic>? route) {
    return route?.settings.name ?? route?.runtimeType.toString() ?? '';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'route_pushed',
      <String, Object?>{
        'route': _routeName(route),
        'previous': _routeName(previousRoute),
      },
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'route_popped',
      <String, Object?>{
        'route': _routeName(route),
        'previous': _routeName(previousRoute),
      },
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'route_removed',
      <String, Object?>{
        'route': _routeName(route),
        'previous': _routeName(previousRoute),
      },
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    SensorDebugTrace.record(
      'SensorContentNavigator',
      'route_replaced',
      <String, Object?>{
        'newRoute': _routeName(newRoute),
        'oldRoute': _routeName(oldRoute),
      },
    );
  }
}
