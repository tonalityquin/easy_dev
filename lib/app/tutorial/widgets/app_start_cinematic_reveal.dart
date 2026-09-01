import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AppStartCinematicReveal extends StatelessWidget {
  const AppStartCinematicReveal({
    super.key,
    required this.animation,
    required this.child,
    required this.reduceMotion,
    this.exiting = false,
  });

  final Animation<double> animation;
  final Widget child;
  final bool reduceMotion;
  final bool exiting;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value.clamp(0.0, 1.0).toDouble();
        final blur = reduceMotion ? 0.0 : 8.0 * (1 - value);
        final scale = reduceMotion
            ? 1.0
            : exiting
                ? 1.0 + (0.015 * (1 - value))
                : 0.985 + (0.015 * value);
        final dy = reduceMotion
            ? 0.0
            : exiting
                ? -4.0 * (1 - value)
                : 6.0 * (1 - value);
        return Opacity(
          opacity: value,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
