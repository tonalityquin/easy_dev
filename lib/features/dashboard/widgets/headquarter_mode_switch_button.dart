import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/side_docks/secondary_side_dock.dart';
import '../../dev/debug/debug_action_recorder.dart';
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

  static const List<_HeadquarterModeTarget> _allTargets =
      <_HeadquarterModeTarget>[
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

  _HeadquarterModeTarget? _targetFor(String modeKey) {
    for (final target in _allTargets) {
      if (target.modeKey == modeKey) return target;
    }
    return null;
  }

  void _trace(BuildContext context, _HeadquarterModeTarget target) {
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

  Future<void> _switchMode(BuildContext context) async {
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

    final builder = appRoutes[target.routeName];
    if (builder == null) {
      showFailedSnackbar(
        context,
        '이동할 화면을 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }

    _trace(context, target);
    onBeforeSwitch();
    if (!context.mounted) return;

    final returnRouteName = target.isSprint ? _currentHeadquarterRoute() : null;
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

  String? _currentHeadquarterRoute() {
    switch (currentModeKey) {
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

  PageRouteBuilder<void> _buildRoute({
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: CommonButton(
        label: '헤드쿼터 모드 전환',
        icon: Icons.swap_horiz_rounded,
        onPressed: () => _switchMode(context),
        expand: true,
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
      ),
    );
  }
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
