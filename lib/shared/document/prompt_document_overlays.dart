import 'package:flutter/material.dart';

import '../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<T?> showPromptFullscreenDocument<T>({
  required BuildContext context,
  required Widget child,
  String barrierLabel = '문서 화면',
}) {
  final tokens = PromptUiTheme.of(context);
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: tokens.scrim,
      barrierLabel: barrierLabel,
      fullscreenDialog: true,
      transitionDuration: reduceMotion ? Duration.zero : PromptUiMotion.overlay,
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : PromptUiMotion.component,
      pageBuilder: (_, __, ___) => PromptUiScope(child: child),
      transitionsBuilder: (_, animation, __, routeChild) {
        if (reduceMotion) return routeChild;
        final curved = CurvedAnimation(
          parent: animation,
          curve: PromptUiMotion.enter,
          reverseCurve: PromptUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: routeChild,
        );
      },
    ),
  );
}
