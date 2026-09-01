import 'package:flutter/material.dart';

import '../application/debug_session_controller.dart';
import 'debug_caution_surface.dart';

class DebugSessionVisualOverlay extends StatelessWidget {
  const DebugSessionVisualOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DebugSessionController.enabled,
      builder: (context, enabled, _) {
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        final duration =
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
        return IgnorePointer(
          child: AnimatedSwitcher(
            duration: duration,
            reverseDuration: duration,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, -0.08),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: enabled
                ? const _ActiveDebugSessionVisual(
                    key: ValueKey<String>('debug_session_active'),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('debug_session_inactive'),
                  ),
          ),
        );
      },
    );
  }
}

class _ActiveDebugSessionVisual extends StatelessWidget {
  const _ActiveDebugSessionVisual({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final top = media.padding.top + 7;
    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 4,
            child: DebugCautionSurface(
              borderRadius: BorderRadius.zero,
              borderWidth: 0,
              child: SizedBox.expand(),
            ),
          ),
        ),
        Positioned(
          top: top,
          left: 10,
          child: DebugCautionSurface(
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: DebugCautionLabel(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 6,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: debugCautionYellow,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'DEBUG ACTIVE',
                      style: TextStyle(
                        color: debugCautionYellow,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
