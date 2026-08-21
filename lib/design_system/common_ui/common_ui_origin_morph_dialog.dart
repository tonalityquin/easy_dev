import 'package:flutter/material.dart';

import 'common_ui_theme.dart';

Future<T?> showCommonOriginMorphDialog<T>({
  required BuildContext context,
  required Rect sourceRect,
  required Size targetSize,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  bool useRootNavigator = true,
  String? barrierLabel,
}) {
  final tokens = CommonUiTheme.of(context);
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
    pageBuilder: (dialogContext, _, __) {
      return CommonUiScope(
        child: Material(
          type: MaterialType.transparency,
          child: Builder(
            builder: (scopedContext) => builder(scopedContext),
          ),
        ),
      );
    },
    transitionBuilder: (transitionContext, animation, secondaryAnimation, child) {
      if (reduceMotion) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final availableWidth = (constraints.maxWidth -
                    media.padding.left -
                    media.padding.right -
                    32)
                .clamp(0.0, constraints.maxWidth)
                .toDouble();
            final availableHeight = (constraints.maxHeight -
                    media.padding.top -
                    media.padding.bottom -
                    media.viewInsets.bottom -
                    32)
                .clamp(0.0, constraints.maxHeight)
                .toDouble();
            final width = targetSize.width.clamp(0.0, availableWidth).toDouble();
            final height =
                targetSize.height.clamp(0.0, availableHeight).toDouble();
            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: tokens.scrim)),
                Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(CommonUiShapes.dialog),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          border: Border.all(color: tokens.borderSubtle),
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.dialog),
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
      return _CommonOriginMorphTransition(
        animation: animation,
        sourceRect: sourceRect,
        targetSize: targetSize,
        child: child,
      );
    },
  );
}

class _CommonOriginMorphTransition extends StatelessWidget {
  const _CommonOriginMorphTransition({
    required this.animation,
    required this.sourceRect,
    required this.targetSize,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Size targetSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final forward = CurvedAnimation(
          parent: animation,
          curve: CommonUiMotion.enter,
          reverseCurve: CommonUiMotion.exit,
        );
        final value = forward.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final safeLeft = media.padding.left + 16;
            final safeTop = media.padding.top + 16;
            final safeRight = constraints.maxWidth - media.padding.right - 16;
            final keyboardTop = constraints.maxHeight - media.viewInsets.bottom;
            final safeBottom = keyboardTop - media.padding.bottom - 16;
            final availableWidth = (safeRight - safeLeft)
                .clamp(0.0, constraints.maxWidth)
                .toDouble();
            final availableHeight = (safeBottom - safeTop)
                .clamp(0.0, constraints.maxHeight)
                .toDouble();
            final width = targetSize.width.clamp(0.0, availableWidth).toDouble();
            final height =
                targetSize.height.clamp(0.0, availableHeight).toDouble();
            final target = Rect.fromLTWH(
              safeLeft + (availableWidth - width) / 2,
              safeTop + (availableHeight - height) / 2,
              width,
              height,
            );
            final rect = Rect.lerp(sourceRect, target, value) ?? target;
            final radius = BorderRadius.lerp(
                  BorderRadius.zero,
                  BorderRadius.circular(CommonUiShapes.dialog),
                  value,
                ) ??
                BorderRadius.circular(CommonUiShapes.dialog);
            final contentOpacity = Curves.easeOut.transform(
              ((value - .16) / .84).clamp(0.0, 1.0).toDouble(),
            );
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Color.lerp(
                          Colors.transparent,
                          tokens.scrim,
                          value,
                        ) ??
                        tokens.scrim,
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised,
                      border: Border.all(color: tokens.borderSubtle),
                      borderRadius: radius,
                      boxShadow: [
                        BoxShadow(
                          color: Color.lerp(
                                Colors.transparent,
                                tokens.shadow,
                                value,
                              ) ??
                              tokens.shadow,
                          blurRadius: 24 * value,
                          offset: Offset(0, 10 * value),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: IgnorePointer(
                        ignoring: value < .98,
                        child: Opacity(
                          opacity: contentOpacity,
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: target.width,
                            maxWidth: target.width,
                            minHeight: target.height,
                            maxHeight: target.height,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
