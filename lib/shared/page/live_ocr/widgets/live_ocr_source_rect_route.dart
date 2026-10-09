import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

class LiveOcrSourceRectRouteController<T> {
  LiveOcrSourceRectRouteController({
    required this.entrySourceRect,
    required this.reduceMotion,
  });

  final Rect entrySourceRect;
  final bool reduceMotion;
  final ValueNotifier<Rect?> _exitTargetRect = ValueNotifier<Rect?>(null);

  Rect? get exitTargetRect => _exitTargetRect.value;

  void setExitTargetRect(Rect? rect) {
    if (rect == null || rect.isEmpty || !rect.isFinite) return;
    _exitTargetRect.value = rect;
  }

  PageRouteBuilder<T> buildRoute({required WidgetBuilder builder}) {
    return PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration:
          reduceMotion ? Duration.zero : CommonUiMotion.component,
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : CommonUiMotion.selection,
      pageBuilder: (context, _, __) => builder(context),
      transitionsBuilder: (context, animation, _, child) {
        if (reduceMotion) return child;
        return ValueListenableBuilder<Rect?>(
          valueListenable: _exitTargetRect,
          child: child,
          builder: (context, exitTarget, transitionChild) {
            return _LiveOcrSourceRectTransition(
              animation: animation,
              entrySourceRect: entrySourceRect,
              exitTargetRect: exitTarget,
              child: transitionChild!,
            );
          },
        );
      },
    );
  }

  void dispose() {
    _exitTargetRect.dispose();
  }
}

class _LiveOcrSourceRectTransition extends StatelessWidget {
  const _LiveOcrSourceRectTransition({
    required this.animation,
    required this.entrySourceRect,
    required this.exitTargetRect,
    required this.child,
  });

  final Animation<double> animation;
  final Rect entrySourceRect;
  final Rect? exitTargetRect;
  final Widget child;

  Rect _safeRect(Rect rect, Size size) {
    final left = rect.left.clamp(0.0, size.width).toDouble();
    final top = rect.top.clamp(0.0, size.height).toDouble();
    final right = rect.right.clamp(left, size.width).toDouble();
    final bottom = rect.bottom.clamp(top, size.height).toDouble();
    final width = math.max(1.0, right - left).toDouble();
    final height = math.max(1.0, bottom - top).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, transitionChild) {
        final size = MediaQuery.sizeOf(context);
        final fullRect = Offset.zero & size;
        final reversing = animation.status == AnimationStatus.reverse;
        final raw = animation.value.clamp(0.0, 1.0).toDouble();
        final progress = reversing
            ? Curves.easeInOutCubic.transform(raw)
            : Curves.easeOutCubic.transform(raw);
        final anchor = reversing
            ? _safeRect(exitTargetRect ?? entrySourceRect, size)
            : _safeRect(entrySourceRect, size);
        final rect = Rect.lerp(anchor, fullRect, progress) ?? fullRect;
        final anchorRadius = reversing
            ? math.min(12.0, anchor.shortestSide / 2)
            : anchor.shortestSide / 2;
        final corner = anchorRadius * (1 - progress);
        final contentOpacity = Curves.easeOut.transform(
          ((progress - .04) / .96).clamp(0.0, 1.0).toDouble(),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withOpacity(.10 * progress),
                ),
              ),
            ),
            Positioned.fill(
              child: ClipPath(
                clipper: _LiveOcrRectClipper(rect: rect, radius: corner),
                child: IgnorePointer(
                  ignoring: reversing || progress < .96,
                  child: Opacity(
                    opacity: contentOpacity,
                    child: transitionChild,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiveOcrRectClipper extends CustomClipper<Path> {
  const _LiveOcrRectClipper({required this.rect, required this.radius});

  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      );
  }

  @override
  bool shouldReclip(covariant _LiveOcrRectClipper oldClipper) {
    return oldClipper.rect != rect || oldClipper.radius != radius;
  }
}
