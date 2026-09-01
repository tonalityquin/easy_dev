import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common_ui_theme.dart';

enum CommonSideDockSide { left, right }

class CommonSideDockPresentationController extends ChangeNotifier {
  CommonSideDockPresentationController({bool visible = true})
      : _visible = visible;

  bool _visible;

  bool get visible => _visible;

  void show() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }
}

Future<T?> showCommonRightSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = '패널',
  bool useRootNavigator = false,
  double maxWidth = 360,
  double widthFactor = 0.92,
  bool barrierDismissible = true,
  CommonSideDockPresentationController? presentationController,
}) {
  return _showCommonSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    maxWidth: maxWidth,
    widthFactor: widthFactor,
    barrierDismissible: barrierDismissible,
    presentationController: presentationController,
    side: CommonSideDockSide.right,
  );
}

Future<T?> showCommonLeftSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = '패널',
  bool useRootNavigator = false,
  double maxWidth = 360,
  double widthFactor = 0.92,
  bool barrierDismissible = true,
  CommonSideDockPresentationController? presentationController,
}) {
  return _showCommonSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    maxWidth: maxWidth,
    widthFactor: widthFactor,
    barrierDismissible: barrierDismissible,
    presentationController: presentationController,
    side: CommonSideDockSide.left,
  );
}

Future<T?> _showCommonSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String barrierLabel,
  required bool useRootNavigator,
  required double maxWidth,
  required double widthFactor,
  required bool barrierDismissible,
  required CommonSideDockPresentationController? presentationController,
  required CommonSideDockSide side,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final logTag = side == CommonSideDockSide.left
      ? 'CommonLeftSideDock'
      : 'CommonRightSideDock';
  debugPrint(
    '[$logTag] push label=$barrierLabel reduceMotion=$reduceMotion side=${side.name}',
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _CommonSideDockRoute<T>(
      builder: builder,
      barrierLabelText: barrierLabel,
      reduceMotion: reduceMotion,
      maxWidth: maxWidth,
      widthFactor: widthFactor,
      scrimDismissible: barrierDismissible,
      presentationController: presentationController,
      side: side,
    ),
  );
}

class _CommonSideDockRoute<T> extends PopupRoute<T> {
  _CommonSideDockRoute({
    required this.builder,
    required this.barrierLabelText,
    required this.reduceMotion,
    required this.maxWidth,
    required this.widthFactor,
    required this.scrimDismissible,
    required this.presentationController,
    required this.side,
  });

  final WidgetBuilder builder;
  final String barrierLabelText;
  final bool reduceMotion;
  final double maxWidth;
  final double widthFactor;
  final bool scrimDismissible;
  final CommonSideDockPresentationController? presentationController;
  final CommonSideDockSide side;

  String get _logTag => side == CommonSideDockSide.left
      ? 'CommonLeftSideDock'
      : 'CommonRightSideDock';
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
        '[$_logTag] close_ignored source=scrim label=$barrierLabelText requested=$_closeRequested dismissible=$scrimDismissible side=${side.name}',
      );
      return;
    }
    _closeRequested = true;
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    debugPrint(
      '[$_logTag] close source=scrim label=$barrierLabelText policy=exactly_once side=${side.name}',
    );
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      _closeRequested = true;
      debugPrint(
        '[$_logTag] pop label=$barrierLabelText source=${_closeSource ?? 'route'} policy=exactly_once side=${side.name}',
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
    final listenables = <Listenable>[
      panelAnimation,
      depthAnimation,
      if (presentationController != null) presentationController!,
    ];
    final listenable = Listenable.merge(listenables);

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
            final presentationVisible = presentationController?.visible ?? true;
            final presentationOpacity = presentationVisible ? 1.0 : 0.0;
            final maxDockWidth =
                (screen.width * widthFactor).clamp(240.0, double.infinity);
            final dockWidth = math.min(maxWidth, maxDockWidth);
            final slideDistance = dockWidth + 44 + 24;
            final isLeft = side == CommonSideDockSide.left;
            final slideX =
                (isLeft ? -1.0 : 1.0) * slideDistance * (1 - progress);
            final depthShiftX = (isLeft ? 10.0 : -10.0) * depth;
            final depthScale = 1.0 - (.008 * depth);
            final panelOpacity =
                progress * (1.0 - (.06 * depth)) * presentationOpacity;

            if (!_layoutLogged) {
              _layoutLogged = true;
              debugPrint(
                '[$_logTag] layout label=$barrierLabelText side=${side.name} anchor=${isLeft ? 'left' : 'right'} slide=${isLeft ? 'negative_x_to_zero' : 'positive_x_to_zero'} screenWidth=${screen.width.toStringAsFixed(1)} dockWidth=${dockWidth.toStringAsFixed(1)} maxWidth=${maxWidth.toStringAsFixed(1)} widthFactor=${widthFactor.toStringAsFixed(2)} sizePolicy=preserved stackDepthMotion=shift10_scale0.992_opacity0.94',
              );
            }

            return PopScope(
              canPop: !reversing,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AbsorbPointer(
                      absorbing: reversing || !presentationVisible,
                      child: ExcludeSemantics(
                        excluding: reversing || !presentationVisible,
                        child: Semantics(
                          button: scrimDismissible,
                          label: scrimDismissible
                              ? '$barrierLabelText 닫기'
                              : barrierLabelText,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _dismissFromScrim(context),
                            child: ColoredBox(
                              color: tokens.scrim.withOpacity(
                                0.22 * progress * presentationOpacity,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: isLeft ? 0 : null,
                    right: isLeft ? null : 0,
                    width: dockWidth,
                    child: AbsorbPointer(
                      absorbing: reversing || !presentationVisible,
                      child: Transform.translate(
                        offset: Offset(slideX + depthShiftX, 0),
                        child: Transform.scale(
                          alignment: isLeft
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          scale: depthScale,
                          child: Opacity(
                            opacity: panelOpacity.clamp(0.0, 1.0).toDouble(),
                            child: _CommonGlassSideDock(
                              width: dockWidth,
                              height: screen.height,
                              side: side,
                              child: SafeArea(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    bottom: keyboardInset,
                                  ),
                                  child: Builder(builder: builder),
                                ),
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
    this.side = CommonSideDockSide.right,
  });

  final double width;
  final double height;
  final Widget child;
  final CommonSideDockSide side;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final radius = side == CommonSideDockSide.left
        ? const BorderRadius.only(
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
          )
        : const BorderRadius.only(
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
  double scrimOpacity = 0.22,
}) {
  return _showOperationsSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    maxWidth: maxWidth,
    widthFactor: widthFactor,
    barrierDismissible: barrierDismissible,
    scrimOpacity: scrimOpacity,
    side: CommonSideDockSide.right,
  );
}

Future<T?> showOperationsLeftSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String barrierLabel = '운영 패널',
  bool useRootNavigator = false,
  double maxWidth = 360,
  double widthFactor = 0.92,
  bool barrierDismissible = true,
  double scrimOpacity = 0.22,
}) {
  return _showOperationsSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: barrierLabel,
    useRootNavigator: useRootNavigator,
    maxWidth: maxWidth,
    widthFactor: widthFactor,
    barrierDismissible: barrierDismissible,
    scrimOpacity: scrimOpacity,
    side: CommonSideDockSide.left,
  );
}

Future<T?> _showOperationsSideDock<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required String barrierLabel,
  required bool useRootNavigator,
  required double maxWidth,
  required double widthFactor,
  required bool barrierDismissible,
  required double scrimOpacity,
  required CommonSideDockSide side,
}) {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  final logTag = side == CommonSideDockSide.left
      ? 'OperationsLeftSideDock'
      : 'OperationsRightSideDock';
  debugPrint(
    '[$logTag] push label=$barrierLabel reduceMotion=$reduceMotion side=${side.name} motion=operations_210_190 translate=${side == CommonSideDockSide.left ? '-22_to_0' : '22_to_0'} opacity=0.90_to_1',
  );
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _OperationsSideDockRoute<T>(
      builder: builder,
      barrierLabelText: barrierLabel,
      reduceMotion: reduceMotion,
      maxWidth: maxWidth,
      widthFactor: widthFactor,
      scrimDismissible: barrierDismissible,
      scrimOpacity: scrimOpacity.clamp(0.0, 1.0).toDouble(),
      side: side,
    ),
  );
}

class _OperationsSideDockRoute<T> extends PopupRoute<T> {
  _OperationsSideDockRoute({
    required this.builder,
    required this.barrierLabelText,
    required this.reduceMotion,
    required this.maxWidth,
    required this.widthFactor,
    required this.scrimDismissible,
    required this.scrimOpacity,
    required this.side,
  });

  final WidgetBuilder builder;
  final String barrierLabelText;
  final bool reduceMotion;
  final double maxWidth;
  final double widthFactor;
  final bool scrimDismissible;
  final double scrimOpacity;
  final CommonSideDockSide side;
  bool _closeRequested = false;
  String? _closeSource;
  bool _layoutLogged = false;

  String get _logTag => side == CommonSideDockSide.left
      ? 'OperationsLeftSideDock'
      : 'OperationsRightSideDock';

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
        '[$_logTag] close_ignored source=scrim label=$barrierLabelText requested=$_closeRequested dismissible=$scrimDismissible side=${side.name}',
      );
      return;
    }
    _closeRequested = true;
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    debugPrint(
      '[$_logTag] close source=scrim label=$barrierLabelText policy=exactly_once side=${side.name}',
    );
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      _closeRequested = true;
      debugPrint(
        '[$_logTag] pop label=$barrierLabelText source=${_closeSource ?? 'route'} policy=exactly_once side=${side.name}',
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
            final isLeft = side == CommonSideDockSide.left;
            final translateX = (isLeft ? -22.0 : 22.0) * (1 - progress);
            final opacity = .90 + (.10 * progress);

            if (!_layoutLogged) {
              _layoutLogged = true;
              debugPrint(
                '[$_logTag] layout label=$barrierLabelText side=${side.name} anchor=${isLeft ? 'left' : 'right'} translate=${isLeft ? '-22_to_0' : '22_to_0'} dockWidth=${dockWidth.toStringAsFixed(1)} screenWidth=${media.size.width.toStringAsFixed(1)} opacity=0.90_to_1 scrim=${scrimOpacity.toStringAsFixed(2)}',
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
                              color: tokens.scrim.withOpacity(scrimOpacity * progress),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: isLeft ? 0 : null,
                    right: isLeft ? null : 0,
                    width: dockWidth,
                    child: Transform.translate(
                      offset: Offset(translateX, 0),
                      child: Opacity(
                        opacity: opacity.clamp(0.0, 1.0).toDouble(),
                        child: _CommonGlassSideDock(
                          width: dockWidth,
                          height: media.size.height,
                          side: side,
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
