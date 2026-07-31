import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';

Future<T?> showCommonFullscreenDocument<T>({
  required BuildContext context,
  required Widget child,
  String barrierLabel = '문서 화면',
}) {
  final tokens = CommonUiTheme.of(context);
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: tokens.scrim,
      barrierLabel: barrierLabel,
      fullscreenDialog: true,
      transitionDuration: reduceMotion ? Duration.zero : CommonUiMotion.overlay,
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : CommonUiMotion.component,
      pageBuilder: (_, __, ___) => CommonUiScope(child: child),
      transitionsBuilder: (_, animation, __, routeChild) {
        if (reduceMotion) return routeChild;
        final curved = CurvedAnimation(
          parent: animation,
          curve: CommonUiMotion.enter,
          reverseCurve: CommonUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: routeChild,
        );
      },
    ),
  );
}
