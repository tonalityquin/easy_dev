import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/headquarter/application/headquarter_dashboard_context.dart';
import '../../../../features/headquarter/application/navigation/headquarter_context_navigation_coordinator.dart';

class HeadquarterContextTopNavigation extends StatefulWidget {
  const HeadquarterContextTopNavigation({
    super.key,
    required this.modeKey,
    required this.currentScreen,
    this.useCommonUi = false,
  });

  final String modeKey;
  final String currentScreen;
  final bool useCommonUi;

  @override
  State<HeadquarterContextTopNavigation> createState() =>
      _HeadquarterContextTopNavigationState();
}

class _HeadquarterContextTopNavigationState
    extends State<HeadquarterContextTopNavigation> {
  bool _pressed = false;
  bool _busy = false;

  Future<void> _openNavigation() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await HeadquarterContextNavigationCoordinator.openNavigationDock(
        context: context,
        currentModeKey: widget.modeKey,
        currentScreen: widget.currentScreen,
        source: 'top_navigation',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = CommonUiTheme.of(context);
    final areaState = context.watch<AreaState>();
    final area = areaState.currentArea.trim().isNotEmpty
        ? areaState.currentArea.trim()
        : '지역 없음';
    final mode = HeadquarterDashboardContext.exactModeLabel(widget.modeKey);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final contextKey = '$area|$mode';

    return Semantics(
      button: true,
      label: '현재 업무 지역 $area, $mode',
      child: AnimatedScale(
        scale: _pressed ? .975 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.standard,
        child: Material(
          color: widget.useCommonUi ? tokens.transparent : Colors.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            onTap: _busy ? null : _openNavigation,
            onTapDown: _busy ? null : (_) => setState(() => _pressed = true),
            onTapCancel: _busy ? null : () => setState(() => _pressed = false),
            onTapUp: _busy ? null : (_) => setState(() => _pressed = false),
            overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.pressed)) {
                return cs.primary.withOpacity(.10);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return cs.primary.withOpacity(.06);
              }
              return null;
            }),
            child: SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.location_solid,
                      size: 17,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        transitionBuilder: (child, animation) {
                          if (reduceMotion) return child;
                          final curved = CurvedAnimation(
                            parent: animation,
                            curve: CommonUiMotion.enter,
                            reverseCurve: CommonUiMotion.exit,
                          );
                          return FadeTransition(
                            opacity: curved,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, .14),
                                end: Offset.zero,
                              ).animate(curved),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          key: ValueKey<String>(contextKey),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            Text(
                              mode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedSwitcher(
                      duration: duration,
                      child: _busy
                          ? SizedBox(
                              key: const ValueKey<String>('busy'),
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: cs.primary,
                              ),
                            )
                          : Icon(
                              CupertinoIcons.chevron_down,
                              key: const ValueKey<String>('ready'),
                              size: 13,
                              color: cs.onSurfaceVariant,
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
  }
}
