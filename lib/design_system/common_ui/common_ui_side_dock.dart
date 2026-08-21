import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common_ui_theme.dart';

Future<T?> showCommonRightSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = '패널',
  bool useRootNavigator = false,
  double maxWidth = 360,
  double widthFactor = 0.92,
  bool barrierDismissible = true,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[CommonRightSideDock] push label=$barrierLabel reduceMotion=$reduceMotion',
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _CommonRightSideDockRoute<T>(
      builder: builder,
      barrierLabelText: barrierLabel,
      reduceMotion: reduceMotion,
      maxWidth: maxWidth,
      widthFactor: widthFactor,
      scrimDismissible: barrierDismissible,
    ),
  );
}

class _CommonRightSideDockRoute<T> extends PopupRoute<T> {
  _CommonRightSideDockRoute({
    required this.builder,
    required this.barrierLabelText,
    required this.reduceMotion,
    required this.maxWidth,
    required this.widthFactor,
    required this.scrimDismissible,
  });

  final WidgetBuilder builder;
  final String barrierLabelText;
  final bool reduceMotion;
  final double maxWidth;
  final double widthFactor;
  final bool scrimDismissible;
  bool _layoutLogged = false;
  bool _closeRequested = false;
  String? _closeSource;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => barrierLabelText;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 240);

  void _dismissFromScrim(BuildContext context) {
    if (!scrimDismissible || _closeRequested) {
      debugPrint(
        '[CommonRightSideDock] close_ignored source=scrim label=$barrierLabelText requested=$_closeRequested dismissible=$scrimDismissible',
      );
      return;
    }
    _closeRequested = true;
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    debugPrint(
      '[CommonRightSideDock] close source=scrim label=$barrierLabelText policy=exactly_once',
    );
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      _closeRequested = true;
      debugPrint(
        '[CommonRightSideDock] pop label=$barrierLabelText source=${_closeSource ?? 'route'} policy=exactly_once',
      );
    }
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final panelAnimation = CurvedAnimation(
      parent: animation,
      curve: reduceMotion ? Curves.linear : const _CommonSideDockSpringCurve(),
      reverseCurve: reduceMotion ? Curves.linear : Curves.easeInCubic,
    );
    final depthAnimation = CurvedAnimation(
      parent: secondaryAnimation,
      curve: reduceMotion ? Curves.linear : Curves.easeOutCubic,
      reverseCurve: reduceMotion ? Curves.linear : Curves.easeInOutCubic,
    );
    final listenable = Listenable.merge(<Listenable>[
      panelAnimation,
      depthAnimation,
    ]);

    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final screen = media.size;
            final keyboardInset = media.viewInsets.bottom;
            final tokens = CommonUiTheme.of(context);
            final progress = reduceMotion
                ? 1.0
                : panelAnimation.value.clamp(0.0, 1.0).toDouble();
            final depth = reduceMotion
                ? 0.0
                : depthAnimation.value.clamp(0.0, 1.0).toDouble();
            final reversing = animation.status == AnimationStatus.reverse;
            final maxDockWidth =
                (screen.width * widthFactor).clamp(240.0, double.infinity);
            final dockWidth = math.min(maxWidth, maxDockWidth);
            final slideDistance = dockWidth + 44 + 24;
            final slideX = slideDistance * (1 - progress);
            final depthShiftX = -10.0 * depth;
            final depthScale = 1.0 - (.008 * depth);
            final panelOpacity = progress * (1.0 - (.06 * depth));

            if (!_layoutLogged) {
              _layoutLogged = true;
              debugPrint(
                '[CommonRightSideDock] layout label=$barrierLabelText screenWidth=${screen.width.toStringAsFixed(1)} dockWidth=${dockWidth.toStringAsFixed(1)} widthFactor=${widthFactor.toStringAsFixed(2)} stackDepthMotion=shift10_scale0.992_opacity0.94',
              );
            }

            return PopScope(
              canPop: !reversing,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: reversing,
                      child: ExcludeSemantics(
                        excluding: reversing,
                        child: Semantics(
                          button: scrimDismissible,
                          label: scrimDismissible
                              ? '$barrierLabelText 닫기'
                              : barrierLabelText,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _dismissFromScrim(context),
                            child: ColoredBox(
                              color: tokens.scrim.withOpacity(0.22 * progress),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: dockWidth,
                    child: Transform.translate(
                      offset: Offset(slideX + depthShiftX, 0),
                      child: Transform.scale(
                        alignment: Alignment.centerRight,
                        scale: depthScale,
                        child: Opacity(
                          opacity: panelOpacity.clamp(0.0, 1.0).toDouble(),
                          child: _CommonGlassSideDock(
                            width: dockWidth,
                            height: screen.height,
                            child: SafeArea(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: keyboardInset),
                                child: Builder(builder: builder),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommonGlassSideDock extends StatelessWidget {
  const _CommonGlassSideDock({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    const radius = BorderRadius.only(
      topLeft: Radius.circular(18),
      bottomLeft: Radius.circular(18),
    );

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: tokens.surface.withOpacity(tokens.isDark ? 0.86 : 0.90),
            border: Border.all(color: tokens.borderSubtle, width: 1),
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                color: tokens.shadow,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}


Future<T?> showOperationsRightSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = '운영 패널',
  bool useRootNavigator = false,
  double maxWidth = 360,
  double widthFactor = 0.92,
  bool barrierDismissible = true,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[OperationsRightSideDock] push label=$barrierLabel reduceMotion=$reduceMotion motion=operations_210_190 translate=22 opacity=0.90_to_1',
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _OperationsRightSideDockRoute<T>(
      builder: builder,
      barrierLabelText: barrierLabel,
      reduceMotion: reduceMotion,
      maxWidth: maxWidth,
      widthFactor: widthFactor,
      scrimDismissible: barrierDismissible,
    ),
  );
}

class _OperationsRightSideDockRoute<T> extends PopupRoute<T> {
  _OperationsRightSideDockRoute({
    required this.builder,
    required this.barrierLabelText,
    required this.reduceMotion,
    required this.maxWidth,
    required this.widthFactor,
    required this.scrimDismissible,
  });

  final WidgetBuilder builder;
  final String barrierLabelText;
  final bool reduceMotion;
  final double maxWidth;
  final double widthFactor;
  final bool scrimDismissible;
  bool _closeRequested = false;
  String? _closeSource;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => barrierLabelText;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 210);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 190);

  void _dismissFromScrim(BuildContext context) {
    if (!scrimDismissible || _closeRequested) {
      debugPrint(
        '[OperationsRightSideDock] close_ignored source=scrim label=$barrierLabelText requested=$_closeRequested dismissible=$scrimDismissible',
      );
      return;
    }
    _closeRequested = true;
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    debugPrint(
      '[OperationsRightSideDock] close source=scrim label=$barrierLabelText policy=exactly_once',
    );
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      _closeRequested = true;
      debugPrint(
        '[OperationsRightSideDock] pop label=$barrierLabelText source=${_closeSource ?? 'route'} policy=exactly_once',
      );
    }
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: reduceMotion ? Curves.linear : CommonUiMotion.enter,
      reverseCurve: reduceMotion ? Curves.linear : CommonUiMotion.exit,
    );

    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final tokens = CommonUiTheme.of(context);
            final progress = reduceMotion
                ? 1.0
                : curved.value.clamp(0.0, 1.0).toDouble();
            final reversing = animation.status == AnimationStatus.reverse;
            final maxDockWidth =
                (media.size.width * widthFactor).clamp(240.0, double.infinity);
            final dockWidth = math.min(maxWidth, maxDockWidth);
            final translateX = 22.0 * (1 - progress);
            final opacity = .90 + (.10 * progress);

            return PopScope(
              canPop: !reversing,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: reversing,
                      child: ExcludeSemantics(
                        excluding: reversing,
                        child: Semantics(
                          button: scrimDismissible,
                          label: scrimDismissible
                              ? '$barrierLabelText 닫기'
                              : barrierLabelText,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _dismissFromScrim(context),
                            child: ColoredBox(
                              color: tokens.scrim.withOpacity(.22 * progress),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: dockWidth,
                    child: Transform.translate(
                      offset: Offset(translateX, 0),
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0).toDouble(),
                        child: _CommonGlassSideDock(
                          width: dockWidth,
                          height: media.size.height,
                          child: SafeArea(
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: media.viewInsets.bottom,
                              ),
                              child: Builder(builder: builder),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CommonSideDockSpringCurve extends Curve {
  const _CommonSideDockSpringCurve();

  @override
  double transform(double t) {
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final value = 1 - e * c;
    return value.clamp(0.0, 1.0).toDouble();
  }
}
