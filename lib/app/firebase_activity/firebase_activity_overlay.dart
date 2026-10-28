import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_monitor.dart';
import 'firebase_activity_status_dialog.dart';

class FirebaseActivityOverlay extends StatelessWidget {
  const FirebaseActivityOverlay({super.key});

  Color _color(FirebaseActivityEvent? event, int running) {
    if (event == null && running == 0) return const Color(0xFF8A98A8);
    if (event?.phase == FirebaseActivityPhase.failed) {
      return const Color(0xFFE65D67);
    }
    if (running > 1) return const Color(0xFF36B6B2);
    if (event?.fromCache == true) return const Color(0xFF9BA5B1);
    switch (event?.kind) {
      case FirebaseActivityKind.read:
        return const Color(0xFF559AF2);
      case FirebaseActivityKind.snapshot:
        return const Color(0xFF43BD99);
      case FirebaseActivityKind.write:
      case FirebaseActivityKind.set:
      case FirebaseActivityKind.create:
      case FirebaseActivityKind.update:
      case FirebaseActivityKind.batch:
      case FirebaseActivityKind.transaction:
        return const Color(0xFFFFB45E);
      case FirebaseActivityKind.delete:
        return const Color(0xFFF47C8D);
      case FirebaseActivityKind.storage:
        return const Color(0xFF9A7CF8);
      case FirebaseActivityKind.authentication:
        return const Color(0xFF4BB7C7);
      case FirebaseActivityKind.initialization:
      case null:
        return const Color(0xFF94A0B2);
    }
  }

  IconData _icon(FirebaseActivityEvent? event, int running) {
    if (event == null && running == 0) return Icons.circle_outlined;
    if (event?.phase == FirebaseActivityPhase.failed) return Icons.error_outline;
    if (running > 1) return Icons.multiple_stop_rounded;
    switch (event?.kind) {
      case FirebaseActivityKind.read:
        return Icons.south_rounded;
      case FirebaseActivityKind.snapshot:
        return Icons.waves_rounded;
      case FirebaseActivityKind.write:
      case FirebaseActivityKind.set:
      case FirebaseActivityKind.create:
      case FirebaseActivityKind.update:
        return Icons.north_rounded;
      case FirebaseActivityKind.delete:
        return Icons.remove_circle_outline_rounded;
      case FirebaseActivityKind.batch:
        return Icons.layers_outlined;
      case FirebaseActivityKind.transaction:
        return Icons.sync_rounded;
      case FirebaseActivityKind.storage:
        return Icons.cloud_upload_outlined;
      case FirebaseActivityKind.authentication:
        return Icons.shield_outlined;
      case FirebaseActivityKind.initialization:
      case null:
        return Icons.cloud_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations;
    final duration = reduced ? Duration.zero : const Duration(milliseconds: 240);
    final monitor = FirebaseActivityMonitor.instance;
    return Positioned(
      right: 12,
      top: media.padding.top + 84,
      child: ValueListenableBuilder<bool>(
        valueListenable: DevAuth.devModeEnabled,
        builder: (context, developer, _) => IgnorePointer(
          ignoring: !developer,
          child: AnimatedBuilder(
            animation: monitor,
            builder: (context, _) {
              final event = monitor.visibleEvent;
              final running = monitor.activeOperationCount;
              final idle = monitor.isIdle && running == 0;
              final color = _color(event, running);
              final count = monitor.totalActivityCount;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: developer
                    ? () => FirebaseActivityStatusDialog.show(context)
                    : null,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(minWidth: 96, minHeight: 38),
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color.lerp(Theme.of(context).colorScheme.surface,
                        color, idle ? 0.08 : 0.18),
                    border: Border.all(color: color.withAlpha(idle ? 110 : 210)),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: idle
                        ? null
                        : <BoxShadow>[
                            BoxShadow(
                              color: color.withAlpha(42),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: duration,
                        child: Icon(
                          _icon(event, running),
                          key: ValueKey<String>(
                              '${idle ? 'idle' : 'active'}_${event?.sequence ?? 0}_${running > 1}'),
                          color: color,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSwitcher(
                            duration: duration,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(opacity: animation, child: child),
                            child: Text(
                              '$count',
                              key: ValueKey<int>(count),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          Text(
                            running > 0 ? '진행 $running' : idle ? '대기' : '활동',
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
