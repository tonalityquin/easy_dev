import 'package:flutter/material.dart';

import '../../../app/init/work_status_notification.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

class HeadquarterWorkStatusHeaderIndicator extends StatefulWidget {
  const HeadquarterWorkStatusHeaderIndicator({super.key});

  @override
  State<HeadquarterWorkStatusHeaderIndicator> createState() =>
      _HeadquarterWorkStatusHeaderIndicatorState();
}

class _HeadquarterWorkStatusHeaderIndicatorState
    extends State<HeadquarterWorkStatusHeaderIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.82, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final componentDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.component;

    if (reduceMotion) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }

    return ValueListenableBuilder<WorkStatusNotificationSnapshot>(
      valueListenable: WorkStatusNotificationController.status,
      builder: (context, status, _) {
        final active = status.isWorking;
        final overdue = status.overdue;
        final desiredPulseDuration = Duration(milliseconds: overdue ? 850 : 1500);
        if (!reduceMotion && _pulseController.duration != desiredPulseDuration) {
          _pulseController.duration = desiredPulseDuration;
          _pulseController.repeat(reverse: true);
        }
        final persistent = status.serviceRunning && status.notificationPersistent;
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
            child: TweenAnimationBuilder<double>(
              key: ValueKey<String>('work_status_${status.source}_${status.updatedAt?.millisecondsSinceEpoch ?? 0}'),
              tween: Tween<double>(begin: 0.96, end: 1),
              duration: componentDuration,
              curve: CommonUiMotion.enter,
              builder: (context, transitionScale, child) => Transform.scale(
                scale: reduceMotion ? 1 : transitionScale,
                child: child,
              ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: border),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: tokens.shadow,
                        blurRadius: active ? 12 : 6,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AnimatedSwitcher(
                        duration: selectionDuration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) => FadeTransition(
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
                        ),
                        child: Icon(
                          overdue
                              ? Icons.notification_important_rounded
                              : active
                                  ? Icons.work_rounded
                                  : Icons.work_history_rounded,
                          key: ValueKey<String>('${active}_$overdue'),
                          size: 18,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: selectionDuration,
                          switchInCurve: CommonUiMotion.enter,
                          switchOutCurve: CommonUiMotion.exit,
                          layoutBuilder: (currentChild, previousChildren) {
                            return Stack(
                              alignment: Alignment.centerLeft,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.16),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: CommonUiMotion.enter,
                                  reverseCurve: CommonUiMotion.exit,
                                ),
                              ),
                              child: child,
                            ),
                          ),
                          child: Text(
                            overdue
                                ? '${status.title} · +${status.overdueMinutes}분'
                                : status.title,
                            key: ValueKey<String>(
                              '${status.title}_${status.overdue}_${status.overdueMinutes}',
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.labelLarge?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      FadeTransition(
                        opacity: active && !reduceMotion
                            ? _pulse
                            : const AlwaysStoppedAnimation<double>(1),
                        child: AnimatedScale(
                          scale: persistent ? 1 : 0.74,
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
          ),
        );
      },
    );
  }
}
