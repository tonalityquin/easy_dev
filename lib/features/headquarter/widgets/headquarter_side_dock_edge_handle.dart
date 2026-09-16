import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../account/applications/user_state.dart';
import '../application/headquarter_side_dock_coordinator.dart';
import '../application/headquarter_side_dock_launcher_controller.dart';

class HeadquarterSideDockEdgeHandle extends StatefulWidget {
  const HeadquarterSideDockEdgeHandle({super.key});

  @override
  State<HeadquarterSideDockEdgeHandle> createState() =>
      _HeadquarterSideDockEdgeHandleState();
}

class _HeadquarterSideDockEdgeHandleState
    extends State<HeadquarterSideDockEdgeHandle> {
  bool _pressed = false;
  bool? _lastEligible;
  bool? _lastVisible;

  void _syncSurfaceState({
    required bool eligible,
    required bool visible,
  }) {
    if (_lastEligible == eligible && _lastVisible == visible) return;
    _lastEligible = eligible;
    _lastVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HeadquarterSideDockLauncherController.updateSurfaceState(
        eligible: eligible,
        visible: visible,
      );
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
    final selectionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return Selector<UserState, bool>(
      selector: (_, state) => state.isLoggedIn,
      builder: (context, loggedIn, _) {
        return ValueListenableBuilder<HeadquarterSideDockLauncherSnapshot>(
          valueListenable: HeadquarterSideDockLauncherController.status,
          builder: (context, launcher, _) {
            final visible =
                launcher.enabled && loggedIn && !launcher.dockOpen;
            _syncSurfaceState(
              eligible: loggedIn,
              visible: visible,
            );

            return IgnorePointer(
              ignoring: !visible,
              child: SafeArea(
                minimum: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedSlide(
                    offset: visible ? Offset.zero : const Offset(-0.72, 0),
                    duration: duration,
                    curve: CommonUiMotion.enter,
                    child: AnimatedOpacity(
                      opacity: visible ? 1 : 0,
                      duration: duration,
                      curve: CommonUiMotion.enter,
                      child: AnimatedScale(
                        scale: visible ? 1 : 0.92,
                        duration: selectionDuration,
                        curve: CommonUiMotion.enter,
                        child: Semantics(
                          button: true,
                          label: '본사 빠른 실행 Side Dock',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (_) => _setPressed(true),
                            onTapUp: (_) => _setPressed(false),
                            onTapCancel: () => _setPressed(false),
                            onTap: () {
                              unawaited(HapticFeedback.selectionClick());
                              unawaited(
                                HeadquarterSideDockCoordinator.open(
                                  source: 'edge_handle',
                                ),
                              );
                            },
                            onLongPress: () =>
                                HeadquarterSideDockLauncherController
                                    .showDeveloperStatus(context),
                            child: SizedBox(
                              width: 48,
                              height: 72,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: AnimatedContainer(
                                  duration: selectionDuration,
                                  curve: CommonUiMotion.enter,
                                  width: _pressed ? 30 : 27,
                                  height: _pressed ? 56 : 60,
                                  decoration: BoxDecoration(
                                    color: _pressed
                                        ? tokens.accentPressed
                                        : tokens.surfaceRaised,
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                    border: Border.all(
                                      color: _pressed
                                          ? tokens.accent
                                          : tokens.borderStrong,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: tokens.shadow,
                                        blurRadius: _pressed ? 8 : 14,
                                        offset: const Offset(4, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: selectionDuration,
                                      switchInCurve: CommonUiMotion.enter,
                                      switchOutCurve: CommonUiMotion.exit,
                                      child: Icon(
                                        Icons.chevron_right_rounded,
                                        key: ValueKey<bool>(_pressed),
                                        size: _pressed ? 19 : 21,
                                        color: _pressed
                                            ? tokens.onAccent
                                            : tokens.accent,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
