import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../dev/debug/debug_action_recorder.dart';
import '../../headquarter/application/headquarter_dashboard_context.dart';
import '../../selector/application/dev_auth.dart';
import '../side_docks/common/headquarter_mode_side_dock.dart';

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
          label: '헤드쿼터 모드 전환',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => _HeadquarterModeSwitchCoordinator.switchMode(
            context: context,
            currentModeKey: currentModeKey,
            currentScreen: currentScreen,
            onBeforeSwitch: onBeforeSwitch,
          ),
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
      child: _HeadquarterModeSwitchChipSurface(
        modeKey: currentModeKey,
        onPressed: () => _HeadquarterModeSwitchCoordinator.switchMode(
          context: context,
          currentModeKey: currentModeKey,
          currentScreen: currentScreen,
          onBeforeSwitch: onBeforeSwitch,
        ),
      ),
    );
  }
}

class _HeadquarterModeSwitchChipSurface extends StatefulWidget {
  const _HeadquarterModeSwitchChipSurface({
    required this.modeKey,
    required this.onPressed,
  });

  final String modeKey;
  final Future<void> Function() onPressed;

  @override
  State<_HeadquarterModeSwitchChipSurface> createState() =>
      _HeadquarterModeSwitchChipSurfaceState();
}

class _HeadquarterModeSwitchChipSurfaceState
    extends State<_HeadquarterModeSwitchChipSurface> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _busy = false;

  Future<void> _invoke() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final label = HeadquarterDashboardContext.exactModeLabel(widget.modeKey);
    final scale = _pressed ? .97 : 1.0;
    final background = _hovered || _focused
        ? Color.alphaBlend(tokens.accent.withOpacity(.08), tokens.accentContainer)
        : tokens.accentContainer;
    final borderColor = _focused
        ? tokens.focusRing
        : tokens.accent.withOpacity(_hovered ? .52 : .34);

    return Semantics(
      button: true,
      enabled: !_busy,
      label: '현재 $label 모드, 헤드쿼터 모드 전환',
      child: FocusableActionDetector(
        enabled: !_busy,
        onShowHoverHighlight: (value) {
          if (mounted) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (mounted) setState(() => _focused = value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _busy ? null : (_) => setState(() => _pressed = true),
          onTapCancel: _busy ? null : () => setState(() => _pressed = false),
          onTapUp: _busy
              ? null
              : (_) {
                  setState(() => _pressed = false);
                  _invoke();
                },
          child: AnimatedScale(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
            curve: CommonUiMotion.standard,
            scale: scale,
            child: AnimatedContainer(
              duration: duration,
              curve: CommonUiMotion.enter,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                border: Border.all(
                  color: borderColor,
                  width: _focused ? 2 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: tokens.shadow.withOpacity(tokens.isDark ? .24 : .10),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: duration,
                    child: _busy
                        ? SizedBox(
                            key: const ValueKey<String>('mode-switch-busy'),
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.onAccentContainer,
                            ),
                          )
                        : Icon(
                            Icons.swap_horiz_rounded,
                            key: const ValueKey<String>('mode-switch-icon'),
                            size: 17,
                            color: tokens.onAccentContainer,
                          ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.08, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      label,
                      key: ValueKey<String>(label),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: tokens.onAccentContainer,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.1,
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
  }
}

class _HeadquarterModeSwitchCoordinator {
  static const List<_HeadquarterModeTarget> _allTargets =
      <_HeadquarterModeTarget>[
    _HeadquarterModeTarget(
      title: '싱글 헤드쿼터',
      routeName: AppRoutes.singleHeadquarterPage,
      modeKey: 'single',
      isSprint: false,
    ),
    _HeadquarterModeTarget(
      title: '더블 헤드쿼터',
      routeName: AppRoutes.doubleHeadquarterPage,
      modeKey: 'double',
      isSprint: false,
    ),
    _HeadquarterModeTarget(
      title: '트리플 헤드쿼터',
      routeName: AppRoutes.tripleHeadquarterPage,
      modeKey: 'triple',
      isSprint: false,
    ),
    _HeadquarterModeTarget(
      title: '마이너 헤드쿼터',
      routeName: AppRoutes.minorHeadquarterPage,
      modeKey: 'minor',
      isSprint: false,
    ),
    _HeadquarterModeTarget(
      title: '스프린트 모드',
      routeName: AppRoutes.sprintModeLoading,
      modeKey: 'sprint',
      isSprint: true,
    ),
  ];

  static _HeadquarterModeTarget? _targetFor(String modeKey) {
    for (final target in _allTargets) {
      if (target.modeKey == modeKey) return target;
    }
    return null;
  }

  static void _trace(
    BuildContext context, {
    required String currentModeKey,
    required String currentScreen,
    required _HeadquarterModeTarget target,
  }) {
    DebugActionRecorder.instance.recordAction(
      '헤드쿼터 모드 전환',
      route: ModalRoute.of(context)?.settings.name,
      meta: <String, dynamic>{
        'screen': currentScreen,
        'action': 'switch_headquarter_mode',
        'from': currentModeKey,
        'to': target.modeKey,
        'toRoute': target.routeName,
      },
    );
  }

  static Future<void> switchMode({
    required BuildContext context,
    required String currentModeKey,
    required String currentScreen,
    required VoidCallback onBeforeSwitch,
  }) async {
    debugPrint(
      '[HQ-MODE-SWITCH] dock_open screen=$currentScreen mode=$currentModeKey',
    );
    final result = await showHeadquarterModeSideDock(
      context: context,
      currentModeKey: currentModeKey,
      currentScreen: currentScreen,
    );
    if (result == null || !context.mounted) {
      debugPrint(
        '[HQ-MODE-SWITCH] dock_closed screen=$currentScreen result=none',
      );
      return;
    }

    if (result.openSecondary) {
      debugPrint(
        '[HQ-MODE-SWITCH] secondary_handoff screen=$currentScreen mode=$currentModeKey',
      );
      await showSecondarySideDock<void>(
        context: context,
        barrierLabel: '운영 관리',
      );
      debugPrint(
        '[HQ-MODE-SWITCH] secondary_closed screen=$currentScreen mode=$currentModeKey',
      );
      return;
    }

    final target = _targetFor(result.modeKey);
    if (target == null || target.modeKey == currentModeKey) return;

    if (target.isSprint) {
      final developerMode = await DevAuth.isDevModeEnabled();
      debugPrint(
        '[HQ-MODE-SWITCH] sprint_guard enabled=$developerMode screen=$currentScreen mode=$currentModeKey',
      );
      if (!developerMode) {
        if (!context.mounted) return;
        showFailedSnackbar(
          context,
          '스프린트 모드는 개발자 모드에서만 사용할 수 있습니다.',
          useCommonUi: true,
        );
        return;
      }
    }

    final builder = appRoutes[target.routeName];
    if (builder == null) {
      showFailedSnackbar(
        context,
        '이동할 화면을 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }

    _trace(
      context,
      currentModeKey: currentModeKey,
      currentScreen: currentScreen,
      target: target,
    );
    onBeforeSwitch();
    if (!context.mounted) return;

    final returnRouteName =
        target.isSprint ? _currentHeadquarterRoute(currentModeKey) : null;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[HQ-MODE-SWITCH] navigate from=$currentModeKey to=${target.modeKey} route=${target.routeName} reduceMotion=$reduceMotion',
    );

    Navigator.of(context).pushReplacement(
      _buildRoute(
        routeName: target.routeName,
        builder: builder,
        isSprint: target.isSprint,
        reduceMotion: reduceMotion,
        arguments: returnRouteName == null
            ? null
            : <String, String>{'returnRouteName': returnRouteName},
      ),
    );
  }

  static String? _currentHeadquarterRoute(String currentModeKey) {
    switch (currentModeKey) {
      case 'single':
        return AppRoutes.singleHeadquarterPage;
      case 'double':
        return AppRoutes.doubleHeadquarterPage;
      case 'triple':
        return AppRoutes.tripleHeadquarterPage;
      case 'minor':
        return AppRoutes.minorHeadquarterPage;
      default:
        return null;
    }
  }

  static PageRouteBuilder<void> _buildRoute({
    required String routeName,
    required WidgetBuilder builder,
    required bool isSprint,
    required bool reduceMotion,
    Object? arguments,
  }) {
    final duration = reduceMotion
        ? Duration.zero
        : Duration(milliseconds: isSprint ? 420 : 240);

    return PageRouteBuilder<void>(
      settings: RouteSettings(name: routeName, arguments: arguments),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
              begin: isSprint
                  ? const Offset(0, .045)
                  : const Offset(.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: isSprint ? .985 : 1,
                end: 1,
              ).animate(curved),
              child: child,
            ),
          ),
        );
      },
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
    HeadquarterDashboardContext.publishMode(
      widget.modeKey,
      source: 'headquarter_mode_switch:init',
    );
  }

  @override
  void didUpdateWidget(covariant _HeadquarterModeContextPublisher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modeKey == widget.modeKey) return;
    HeadquarterDashboardContext.publishMode(
      widget.modeKey,
      source: 'headquarter_mode_switch:update',
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

@immutable
class _HeadquarterModeTarget {
  const _HeadquarterModeTarget({
    required this.title,
    required this.routeName,
    required this.modeKey,
    required this.isSprint,
  });

  final String title;
  final String routeName;
  final String modeKey;
  final bool isSprint;
}
