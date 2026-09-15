import 'package:flutter/material.dart';

import '../../../app/init/work_status_notification.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

class HeadquarterWorkStatusHeaderIndicator extends StatelessWidget {
  const HeadquarterWorkStatusHeaderIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final componentDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.component;

    return ValueListenableBuilder<WorkStatusNotificationSnapshot>(
      valueListenable: WorkStatusNotificationController.status,
      builder: (context, status, _) {
        final active = status.isWorking;
        final persistent =
            status.serviceRunning && status.notificationPersistent;
        final foreground = active ? tokens.accent : tokens.textSecondary;
        final background = active
            ? tokens.accentContainer.withOpacity(tokens.isDark ? 0.48 : 0.72)
            : tokens.surfaceSelected;
        final border = active
            ? tokens.accent.withOpacity(tokens.isDark ? 0.60 : 0.38)
            : tokens.borderSubtle;

        return Semantics(
          label: status.title,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () =>
                WorkStatusNotificationController.showDeveloperStatus(context),
            child: AnimatedScale(
              scale: status.serviceRunning ? 1 : 0.96,
              duration: componentDuration,
              curve: CommonUiMotion.enter,
              child: AnimatedOpacity(
                opacity: status.serviceRunning ? 1 : 0.72,
                duration: componentDuration,
                curve: CommonUiMotion.enter,
                child: AnimatedContainer(
                  duration: componentDuration,
                  curve: CommonUiMotion.enter,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.shadow,
                        blurRadius: active ? 12 : 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: selectionDuration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.88, end: 1).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: CommonUiMotion.enter,
                                  reverseCurve: CommonUiMotion.exit,
                                ),
                              ),
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          active ? Icons.work_rounded : Icons.work_history_rounded,
                          key: ValueKey<bool>(active),
                          size: 18,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 7),
                      AnimatedSwitcher(
                        duration: selectionDuration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.16),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: CommonUiMotion.enter,
                              reverseCurve: CommonUiMotion.exit,
                            ),
                          );
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          status.title,
                          key: ValueKey<String>(status.title),
                          style: textTheme.labelLarge?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      AnimatedScale(
                        scale: persistent ? 1 : 0.74,
                        duration: selectionDuration,
                        curve: CommonUiMotion.enter,
                        child: AnimatedOpacity(
                          opacity: persistent ? 1 : 0.42,
                          duration: selectionDuration,
                          curve: CommonUiMotion.enter,
                          child: AnimatedContainer(
                            duration: selectionDuration,
                            curve: CommonUiMotion.enter,
                            width: persistent ? 7 : 5,
                            height: persistent ? 7 : 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: foreground.withOpacity(
                                persistent ? 0.92 : 0.34,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
