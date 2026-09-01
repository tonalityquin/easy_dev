import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../headquarter/application/headquarter_dashboard_context.dart';
import '../../headquarter/application/navigation/headquarter_context_navigation_coordinator.dart';

@immutable
class HeadquarterModeSwitchButton extends StatelessWidget {
  const HeadquarterModeSwitchButton({
    super.key,
    required this.currentModeKey,
    required this.currentScreen,
    required this.onBeforeSwitch,
  });

  final String currentModeKey;
  final String currentScreen;
  final VoidCallback onBeforeSwitch;

  @override
  Widget build(BuildContext context) {
    return _HeadquarterModeContextPublisher(
      modeKey: currentModeKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: CommonButton(
          label: '업무 지역 선택',
          icon: Icons.location_on_outlined,
          onPressed: () async {
            onBeforeSwitch();
            await HeadquarterContextNavigationCoordinator.openNavigationDock(
              context: context,
              currentModeKey: currentModeKey,
              currentScreen: currentScreen,
              source: 'headquarter_work_area_button',
            );
          },
          expand: true,
          variant: CommonButtonVariant.secondary,
          haptic: CommonHaptic.selection,
        ),
      ),
    );
  }
}

@immutable
class HeadquarterModeSwitchChip extends StatelessWidget {
  const HeadquarterModeSwitchChip({
    super.key,
    required this.currentModeKey,
    required this.currentScreen,
    required this.onBeforeSwitch,
  });

  final String currentModeKey;
  final String currentScreen;
  final VoidCallback onBeforeSwitch;

  @override
  Widget build(BuildContext context) {
    return _HeadquarterModeContextPublisher(
      modeKey: currentModeKey,
      child: _HeadquarterWorkAreaChipSurface(
        currentScreen: currentScreen,
        currentModeKey: currentModeKey,
        onBeforeSwitch: onBeforeSwitch,
      ),
    );
  }
}

class _HeadquarterWorkAreaChipSurface extends StatefulWidget {
  const _HeadquarterWorkAreaChipSurface({
    required this.currentScreen,
    required this.currentModeKey,
    required this.onBeforeSwitch,
  });

  final String currentScreen;
  final String currentModeKey;
  final VoidCallback onBeforeSwitch;

  @override
  State<_HeadquarterWorkAreaChipSurface> createState() =>
      _HeadquarterWorkAreaChipSurfaceState();
}

class _HeadquarterWorkAreaChipSurfaceState
    extends State<_HeadquarterWorkAreaChipSurface> {
  bool _pressed = false;
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    widget.onBeforeSwitch();
    try {
      await HeadquarterContextNavigationCoordinator.openNavigationDock(
        context: context,
        currentModeKey: widget.currentModeKey,
        currentScreen: widget.currentScreen,
        source: 'headquarter_work_area_chip',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.press;
    return Semantics(
      button: true,
      label: '업무 지역 선택',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _busy ? null : (_) => setState(() => _pressed = true),
        onTapCancel: _busy ? null : () => setState(() => _pressed = false),
        onTapUp: _busy
            ? null
            : (_) {
                setState(() => _pressed = false);
                _open();
              },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: duration,
          curve: CommonUiMotion.standard,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            curve: CommonUiMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              border: Border.all(color: tokens.accent.withOpacity(.42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: duration,
                  child: _busy
                      ? SizedBox(
                          key: const ValueKey<String>('work-area-busy'),
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tokens.onAccentContainer,
                          ),
                        )
                      : Icon(
                          Icons.location_on_outlined,
                          key: const ValueKey<String>('work-area-idle'),
                          size: 17,
                          color: tokens.onAccentContainer,
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  '업무 지역',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.onAccentContainer,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadquarterModeContextPublisher extends StatefulWidget {
  const _HeadquarterModeContextPublisher({
    required this.modeKey,
    required this.child,
  });

  final String modeKey;
  final Widget child;

  @override
  State<_HeadquarterModeContextPublisher> createState() =>
      _HeadquarterModeContextPublisherState();
}

class _HeadquarterModeContextPublisherState
    extends State<_HeadquarterModeContextPublisher> {
  @override
  void initState() {
    super.initState();
    _publish();
  }

  @override
  void didUpdateWidget(covariant _HeadquarterModeContextPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modeKey != widget.modeKey) _publish();
  }

  void _publish() {
    HeadquarterDashboardContext.publishMode(
      widget.modeKey,
      source: 'headquarter_work_area_switch',
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
