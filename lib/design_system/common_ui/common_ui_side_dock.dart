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
  });

  final WidgetBuilder builder;
  final String barrierLabelText;
  final bool reduceMotion;
  final double maxWidth;
  final double widthFactor;
  bool _layoutLogged = false;
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
    _closeSource = 'scrim';
    HapticFeedback.lightImpact();
    debugPrint(
      '[CommonRightSideDock] close source=scrim label=$barrierLabelText',
    );
    Navigator.of(context).pop();
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    if (popped) {
      debugPrint(
        '[CommonRightSideDock] pop label=$barrierLabelText source=${_closeSource ?? 'route'}',
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

    return CommonUiScope(
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: panelAnimation,
          builder: (context, _) {
            final media = MediaQuery.of(context);
            final screen = media.size;
            final keyboardInset = media.viewInsets.bottom;
            final tokens = CommonUiTheme.of(context);
            final progress = reduceMotion
                ? 1.0
                : panelAnimation.value.clamp(0.0, 1.0).toDouble();
            final maxDockWidth =
                (screen.width * widthFactor).clamp(240.0, double.infinity);
            final dockWidth = math.min(maxWidth, maxDockWidth);
            final slideDistance = dockWidth + 44 + 24;
            final slideX = slideDistance * (1 - progress);

            if (!_layoutLogged) {
              _layoutLogged = true;
              debugPrint(
                '[CommonRightSideDock] layout label=$barrierLabelText screenWidth=${screen.width.toStringAsFixed(1)} dockWidth=${dockWidth.toStringAsFixed(1)} widthFactor=${widthFactor.toStringAsFixed(2)}',
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    button: true,
                    label: '$barrierLabelText 닫기',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _dismissFromScrim(context),
                      child: ColoredBox(
                        color: tokens.scrim.withOpacity(0.22 * progress),
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
                    offset: Offset(slideX, 0),
                    child: Opacity(
                      opacity: progress,
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
              ],
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
