import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../dev/debug/debug_action_recorder.dart';

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
      title: '더블 헤드쿼터로 이동',
      routeName: AppRoutes.doubleHeadquarterPage,
      icon: Icons.view_week_rounded,
      modeKey: 'double',
    ),
    _HeadquarterModeTarget(
      title: '트리플 헤드쿼터로 이동',
      routeName: AppRoutes.tripleHeadquarterPage,
      icon: Icons.apartment_rounded,
      modeKey: 'triple',
    ),
    _HeadquarterModeTarget(
      title: '마이너 헤드쿼터로 이동',
      routeName: AppRoutes.minorHeadquarterPage,
      icon: Icons.tune_rounded,
      modeKey: 'minor',
    ),
    _HeadquarterModeTarget(
      title: '스프린트 모드',
      routeName: AppRoutes.sprintModeLoading,
      icon: Icons.bolt_rounded,
      modeKey: 'sprint',
      isSprint: true,
    ),
  ];

  List<_HeadquarterModeTarget> get _targets {
    return _allTargets
        .where((target) => target.modeKey != currentModeKey)
        .toList(growable: false);
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

  Future<_HeadquarterModeTarget?> _pickTarget(BuildContext context) {
    return showPromptDialog<_HeadquarterModeTarget>(
      context: context,
      builder: (dialogContext) {
        final tokens = PromptUiTheme.of(dialogContext);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '헤드쿼터 모드 전환',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  PromptIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    haptic: PromptHaptic.selection,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ..._targets.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PromptAnimatedReveal(
                        delay: Duration(milliseconds: 45 * entry.key),
                        offset: const Offset(0, 0.025),
                        child: PromptButton(
                          label: entry.value.title,
                          icon: entry.value.icon,
                          onPressed: () => Navigator.of(dialogContext)
                              .pop(entry.value),
                          expand: true,
                          variant: entry.value.isSprint
                              ? PromptButtonVariant.primary
                              : PromptButtonVariant.secondary,
                          haptic: PromptHaptic.selection,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _switchMode(BuildContext context) async {
    final target = await _pickTarget(context);
    if (target == null || !context.mounted) return;

    final builder = appRoutes[target.routeName];
    if (builder == null) {
      showFailedSnackbar(
        context,
        '이동할 화면을 찾을 수 없습니다.',
        usePromptUi: true,
      );
      return;
    }

    _trace(context, target);
    onBeforeSwitch();
    if (!context.mounted) return;

    final returnRouteName = target.isSprint ? _currentHeadquarterRoute() : null;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

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
          curve: PromptUiMotion.enter,
          reverseCurve: PromptUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: isSprint
                  ? const Offset(0, 0.045)
                  : const Offset(0.035, 0),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: isSprint ? 0.985 : 1,
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
      child: PromptButton(
        label: '헤드쿼터 모드 전환',
        icon: Icons.swap_horiz_rounded,
        onPressed: () => _switchMode(context),
        expand: true,
        variant: PromptButtonVariant.secondary,
        haptic: PromptHaptic.selection,
      ),
    );
  }
}

@immutable
class _HeadquarterModeTarget {
  const _HeadquarterModeTarget({
    required this.title,
    required this.routeName,
    required this.icon,
    required this.modeKey,
    this.isSprint = false,
  });

  final String title;
  final String routeName;
  final IconData icon;
  final String modeKey;
  final bool isSprint;
}
