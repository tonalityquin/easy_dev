import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';
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
      icon: Icons.view_week,
      modeKey: 'double',
    ),
    _HeadquarterModeTarget(
      title: '트리플 헤드쿼터로 이동',
      routeName: AppRoutes.tripleHeadquarterPage,
      icon: Icons.apartment,
      modeKey: 'triple',
    ),
    _HeadquarterModeTarget(
      title: '마이너 헤드쿼터로 이동',
      routeName: AppRoutes.minorHeadquarterPage,
      icon: Icons.tune,
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

  void _trace(
    BuildContext context,
    _HeadquarterModeTarget target,
  ) {
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
    final colorScheme = Theme.of(context).colorScheme;

    return showDialog<_HeadquarterModeTarget>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '헤드쿼터 모드 전환',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.close,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._targets.map(
                  (target) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ModeSwitchDialogOption(
                      target: target,
                      onTap: () => Navigator.of(dialogContext).pop(target),
                    ),
                  ),
                ),
              ],
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이동할 화면을 찾을 수 없습니다.')),
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
        : Duration(milliseconds: isSprint ? 420 : 220);

    return PageRouteBuilder<void>(
      settings: RouteSettings(name: routeName, arguments: arguments),
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) {
        return builder(context);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final slide = Tween<Offset>(
          begin: isSprint
              ? const Offset(0, 0.06)
              : const Offset(-1.0, 0),
          end: Offset.zero,
        ).animate(curved);
        final fade = Tween<double>(begin: 0, end: 1).animate(curved);
        final scale = Tween<double>(
          begin: isSprint ? 0.985 : 1,
          end: 1,
        ).animate(curved);

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: scale,
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
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.swap_horiz),
          label: const Text('헤드쿼터 모드 전환'),
          style: _switchButtonStyle(context),
          onPressed: () => _switchMode(context),
        ),
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

class _ModeSwitchDialogOption extends StatelessWidget {
  const _ModeSwitchDialogOption({
    required this.target,
    required this.onTap,
  });

  final _HeadquarterModeTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.85),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: target.isSprint
                      ? colorScheme.primaryContainer
                      : colorScheme.primary.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  target.icon,
                  color: target.isSprint
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  target.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ButtonStyle _switchButtonStyle(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: colorScheme.surface,
    foregroundColor: colorScheme.onSurface,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(
      color: colorScheme.outlineVariant.withOpacity(0.85),
      width: 1,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
      (states) => states.contains(MaterialState.pressed)
          ? colorScheme.outlineVariant.withOpacity(0.12)
          : null,
    ),
  );
}
