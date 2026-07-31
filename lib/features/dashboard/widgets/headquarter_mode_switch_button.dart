import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/pages/secondary_page.dart';
import '../../dev/debug/debug_action_recorder.dart';
import '../../selector/application/dev_auth.dart';

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

  static const String _secondaryRouteName = 'secondary_page';

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
    _HeadquarterModeTarget(
      title: 'Secondary Page',
      routeName: _secondaryRouteName,
      icon: Icons.developer_mode_rounded,
      modeKey: 'secondary',
      isSecondary: true,
    ),
  ];

  List<_HeadquarterModeTarget> _targets(bool developerMode) {
    return _allTargets
        .where((target) => target.modeKey != currentModeKey)
        .where((target) => developerMode || !target.isSecondary)
        .toList(growable: false);
  }

  void _trace(BuildContext context, _HeadquarterModeTarget target) {
    DebugActionRecorder.instance.recordAction(
      target.isSecondary ? 'Secondary Page 이동' : '헤드쿼터 모드 전환',
      route: ModalRoute.of(context)?.settings.name,
      meta: <String, dynamic>{
        'screen': currentScreen,
        'action': target.isSecondary
            ? 'open_secondary_page'
            : 'switch_headquarter_mode',
        'from': currentModeKey,
        'to': target.modeKey,
        'toRoute': target.routeName,
      },
    );
  }

  Future<_HeadquarterModeTarget?> _pickTarget(BuildContext context) async {
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    debugPrint(
      '[HQ-MODE-SWITCH] sheet_open screen=$currentScreen mode=$currentModeKey developerMode=$developerMode',
    );
    if (!context.mounted) return null;

    final targets = _targets(developerMode);
    return showCommonDialog<_HeadquarterModeTarget>(
      context: context,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
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
                          BorderRadius.circular(CommonUiShapes.control),
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
                  CommonIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    haptic: CommonHaptic.selection,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...targets.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CommonAnimatedReveal(
                        delay: Duration(milliseconds: 45 * entry.key),
                        offset: const Offset(0, 0.025),
                        child: CommonButton(
                          label: entry.value.title,
                          icon: entry.value.icon,
                          onPressed: () => Navigator.of(dialogContext)
                              .pop(entry.value),
                          expand: true,
                          variant: entry.value.isSprint
                              ? CommonButtonVariant.primary
                              : CommonButtonVariant.secondary,
                          haptic: CommonHaptic.selection,
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

    if (target.isSecondary) {
      await _openSecondaryPage(context, target);
      return;
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

  Future<void> _openSecondaryPage(
    BuildContext context,
    _HeadquarterModeTarget target,
  ) async {
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    debugPrint(
      '[HQ-MODE-SWITCH][SECONDARY] request screen=$currentScreen mode=$currentModeKey developerMode=$developerMode',
    );
    if (!context.mounted) return;

    if (!developerMode) {
      debugPrint(
        '[HQ-MODE-SWITCH][SECONDARY] blocked developerMode=false screen=$currentScreen mode=$currentModeKey',
      );
      showFailedSnackbar(
        context,
        '개발자 모드가 꺼져 있어 Secondary Page를 열 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }

    _trace(context, target);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: 'Secondary Page 이동',
      initialMessage: '본사 대시보드에서 Secondary Page 이동 요청을 확인합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 이동 진단 로그를 표시합니다.',
      standardModeMessage: '개발자 모드 OFF: Secondary Page 이동을 차단합니다.',
    );
    trace.log(
      'screen=$currentScreen currentMode=$currentModeKey target=${target.routeName}',
      progress: 0.45,
    );
    trace.log('Secondary Page 전환 애니메이션을 준비합니다.', progress: 0.78);
    await trace.succeed('Secondary Page 이동 준비가 완료되었습니다.');
    if (!context.mounted) return;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    debugPrint(
      '[HQ-MODE-SWITCH][SECONDARY] navigate screen=$currentScreen mode=$currentModeKey reduceMotion=$reduceMotion',
    );
    await Navigator.of(context).push(
      _buildSecondaryRoute(reduceMotion: reduceMotion),
    );
    debugPrint(
      '[HQ-MODE-SWITCH][SECONDARY] returned screen=$currentScreen mode=$currentModeKey',
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

  PageRouteBuilder<void> _buildSecondaryRoute({required bool reduceMotion}) {
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 360);
    return PageRouteBuilder<void>(
      settings: const RouteSettings(name: _secondaryRouteName),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SecondaryPage(),
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
              begin: const Offset(0.035, 0.012),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
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
    required this.icon,
    required this.modeKey,
    this.isSprint = false,
    this.isSecondary = false,
  });

  final String title;
  final String routeName;
  final IconData icon;
  final String modeKey;
  final bool isSprint;
  final bool isSecondary;
}
