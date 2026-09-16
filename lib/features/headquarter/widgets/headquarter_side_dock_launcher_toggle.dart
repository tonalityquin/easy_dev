import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/headquarter_side_dock_launcher_controller.dart';

class HeadquarterSideDockLauncherToggle extends StatelessWidget {
  const HeadquarterSideDockLauncherToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return ValueListenableBuilder<HeadquarterSideDockLauncherSnapshot>(
      valueListenable: HeadquarterSideDockLauncherController.status,
      builder: (context, launcher, _) {
        final enabled = launcher.enabled;
        final foreground = enabled ? tokens.accent : tokens.textSecondary;
        final background = enabled
            ? tokens.accentContainer.withOpacity(tokens.isDark ? 0.45 : 0.68)
            : tokens.surfaceSelected;
        final border = enabled
            ? tokens.accent.withOpacity(tokens.isDark ? 0.58 : 0.36)
            : tokens.borderSubtle;

        return Semantics(
          button: true,
          toggled: enabled,
          label: '본사 빠른 실행 Side Dock 빠른 열기',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              unawaited(HapticFeedback.selectionClick());
              unawaited(
                HeadquarterSideDockLauncherController.setEnabled(
                  !enabled,
                  source: 'headquarter_dashboard_toggle',
                ),
              );
            },
            onLongPress: () => HeadquarterSideDockLauncherController
                .showDeveloperStatus(context),
            child: AnimatedContainer(
              duration: duration,
              curve: CommonUiMotion.enter,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.84, end: 1).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: CommonUiMotion.enter,
                          ),
                        ),
                        child: child,
                      ),
                    ),
                    child: Icon(
                      enabled
                          ? Icons.view_sidebar_rounded
                          : Icons.view_sidebar_outlined,
                      key: ValueKey<bool>(enabled),
                      size: 17,
                      color: foreground,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Dock',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(width: 7),
                  AnimatedContainer(
                    duration: duration,
                    curve: CommonUiMotion.enter,
                    width: 32,
                    height: 18,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: enabled
                          ? tokens.accent.withOpacity(0.22)
                          : tokens.surfaceDisabled,
                      borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                    ),
                    child: AnimatedAlign(
                      duration: duration,
                      curve: CommonUiMotion.enter,
                      alignment: enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: duration,
                        curve: CommonUiMotion.enter,
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled ? tokens.accent : tokens.textDisabled,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    child: Text(
                      enabled ? 'ON' : 'OFF',
                      key: ValueKey<bool>(enabled),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
