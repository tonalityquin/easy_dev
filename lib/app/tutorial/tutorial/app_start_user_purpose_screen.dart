import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/selector/application/dev_auth.dart';

class AppStartUserPurposeScreen extends StatefulWidget {
  const AppStartUserPurposeScreen({super.key});

  @override
  State<AppStartUserPurposeScreen> createState() =>
      _AppStartUserPurposeScreenState();
}

class _AppStartUserPurposeScreenState extends State<AppStartUserPurposeScreen> {
  AppStartUserPurpose? _selected;
  bool _busy = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    AppStartDebugTrace.log('user_purpose', 'screen_init');
    DevAuth.isDevModeEnabled();
    _loadSavedPurpose();
  }

  Future<void> _loadSavedPurpose() async {
    final saved = await AppStartFlowPrefs.getUserPurpose();
    if (!mounted || saved == null) return;
    setState(() => _selected = saved);
    AppStartDebugTrace.log(
      'user_purpose',
      'saved_purpose_loaded',
      meta: <String, Object?>{'purpose': saved.storageValue},
    );
  }

  IconData _iconForPurpose(AppStartUserPurpose purpose) {
    return switch (purpose) {
      AppStartUserPurpose.branchEmployee => Icons.business_rounded,
      AppStartUserPurpose.headOfficeEmployee => Icons.domain_rounded,
      AppStartUserPurpose.tabletInstallation => Icons.tablet_android_rounded,
      AppStartUserPurpose.commuteRecorder => Icons.schedule_rounded,
      AppStartUserPurpose.personal => Icons.person_rounded,
    };
  }

  String _permissionStepLabel(int step) {
    return switch (step) {
      1 => '안내',
      2 => '알림',
      3 => '위치',
      4 => '배터리',
      5 => '카메라',
      6 => '다른 앱 위에 표시',
      7 => '마이크',
      _ => '설정',
    };
  }

  void _selectPurpose(AppStartUserPurpose purpose) {
    if (_busy || _selected == purpose) return;
    HapticFeedback.selectionClick();
    setState(() => _selected = purpose);
    AppStartDebugTrace.log(
      'user_purpose',
      'purpose_selected',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'steps': purpose.permissionStepNumbers.join(','),
        'policyPostSetup':
            purpose.skipsPolicyAndPostSetup ? 'skip' : 'required',
      },
    );
  }

  Future<void> _confirmPurpose() async {
    final selected = _selected;
    if (_busy || selected == null) return;
    setState(() => _busy = true);
    AppStartDebugTrace.log(
      'user_purpose',
      'purpose_confirm_start',
      meta: <String, Object?>{'purpose': selected.storageValue},
    );
    try {
      await AppStartFlowPrefs.setUserPurpose(selected);
      AppStartDebugTrace.log(
        'user_purpose',
        'purpose_confirm_success',
        meta: <String, Object?>{
          'purpose': selected.storageValue,
          'stepCount': selected.permissionStepNumbers.length,
          'policyPostSetup':
              selected.skipsPolicyAndPostSetup ? 'skip' : 'required',
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoutes.appStartPermissionNotice,
      );
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'user_purpose',
        'purpose_confirm_failure',
        meta: <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeveloperStatus() async {
    await AppStartDebugTrace.showDeveloperStatus(
      context,
      title: '사용 환경 선택 개발자 상태',
      description: '최초 실행 사용자 유형 선택 흐름의 debugPrint 코드를 복사할 수 있습니다.',
      scope: 'user_purpose',
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return _PurposeEntrance(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: tokens.accentContainer,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.manage_accounts_rounded,
              size: 42,
              color: tokens.onAccentContainer,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '어떻게 사용하시나요?',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              '사용 환경을 선택하면 필요한 권한만 순서대로 안내합니다.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: tokens.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurposeCard(
    BuildContext context,
    AppStartUserPurpose purpose,
    int index,
  ) {
    return _PurposeEntrance(
      delay: Duration(milliseconds: 45 * (index + 1)),
      child: _PurposeSelectionCard(
        purpose: purpose,
        icon: _iconForPurpose(purpose),
        selected: _selected == purpose,
        enabled: !_busy,
        onTap: () => _selectPurpose(purpose),
      ),
    );
  }

  Widget _buildPurposeList(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 680;
        if (!twoColumns) {
          return Column(
            children: [
              for (var i = 0; i < AppStartUserPurpose.values.length; i++) ...[
                _buildPurposeCard(
                  context,
                  AppStartUserPurpose.values[i],
                  i,
                ),
                if (i < AppStartUserPurpose.values.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          );
        }

        const spacing = 12.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < AppStartUserPurpose.values.length; i++)
              SizedBox(
                width: width,
                child: _buildPurposeCard(
                  context,
                  AppStartUserPurpose.values[i],
                  i,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionPreview(BuildContext context) {
    final selected = _selected;
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return AnimatedSize(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.layout,
      curve: CommonUiMotion.standard,
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: selected == null
            ? const SizedBox(key: ValueKey<String>('empty'))
            : Container(
                key: ValueKey<AppStartUserPurpose>(selected),
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(CommonUiShapes.card),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: tokens.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${selected.label} 권한 설정',
                            style: textTheme.titleMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          '${selected.permissionStepNumbers.length}단계',
                          style: textTheme.labelLarge?.copyWith(
                            color: tokens.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selected.permissionStepNumbers
                          .map(
                            (step) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.accentContainer,
                                borderRadius: BorderRadius.circular(
                                  CommonUiShapes.pill,
                                ),
                                border: Border.all(
                                  color: tokens.accent.withOpacity(
                                    tokens.isDark ? 0.52 : 0.28,
                                  ),
                                ),
                              ),
                              child: Text(
                                _permissionStepLabel(step),
                                style: textTheme.labelMedium?.copyWith(
                                  color: tokens.onAccentContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      selected.skipsPolicyAndPostSetup
                          ? '권한 설정 완료 후 정책 및 Google 후속 설정 화면을 건너뜁니다.'
                          : selected.permissionStepNumbers.length == 2
                              ? '추가 권한은 요청하지 않습니다.'
                              : '선택한 사용 환경에 필요한 단계만 표시합니다.',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final iconBrightness =
              tokens.isDark ? Brightness.light : Brightness.dark;

          return PopScope(
            canPop: false,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.surface,
                statusBarIconBrightness: iconBrightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: iconBrightness,
                systemNavigationBarDividerColor: tokens.borderSubtle,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                appBar: AppBar(
                  title: const Text('사용 환경 선택'),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  actions: [
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled) return const SizedBox.shrink();
                        return IconButton(
                          tooltip: '개발자 상태',
                          onPressed: _showDeveloperStatus,
                          icon: const Icon(Icons.terminal_rounded),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
                body: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                              child: Column(
                                children: [
                                  _buildHeader(context),
                                  const SizedBox(height: 26),
                                  _buildPurposeList(context),
                                  const SizedBox(height: 16),
                                  _buildPermissionPreview(context),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              border: Border(
                                top: BorderSide(color: tokens.borderSubtle),
                              ),
                            ),
                            child: CommonButton(
                              label: _busy ? '저장 중' : '이 유형으로 시작',
                              icon: Icons.arrow_forward_rounded,
                              onPressed:
                                  _selected == null || _busy ? null : _confirmPurpose,
                              loading: _busy,
                              expand: true,
                              haptic: CommonHaptic.selection,
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
      ),
    );
  }
}

class _PurposeSelectionCard extends StatefulWidget {
  const _PurposeSelectionCard({
    required this.purpose,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppStartUserPurpose purpose;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_PurposeSelectionCard> createState() => _PurposeSelectionCardState();
}

class _PurposeSelectionCardState extends State<_PurposeSelectionCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = widget.selected;

    return AnimatedScale(
      scale: _pressed && widget.enabled ? 0.985 : 1,
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.standard,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: selected ? 18 : 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.enabled ? widget.onTap : null,
            onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
            onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
            onTapCancel: widget.enabled ? () => _setPressed(false) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.accentContainer
                          : tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      widget.icon,
                      color: selected
                          ? tokens.onAccentContainer
                          : tokens.iconSecondary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.purpose.label,
                          style: textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.purpose.description,
                          style: textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '설정 ${widget.purpose.permissionStepNumbers.length}단계',
                          style: textTheme.labelMedium?.copyWith(
                            color: selected
                                ? tokens.accent
                                : tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: Curves.linear,
                    switchOutCurve: Curves.linear,
                    transitionBuilder: (child, animation) {
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(scale: fade, child: child),
                      );
                    },
                    child: selected
                        ? Icon(
                            Icons.check_circle_rounded,
                            key: const ValueKey<String>('selected'),
                            color: tokens.accent,
                            size: 28,
                          )
                        : Icon(
                            Icons.radio_button_unchecked_rounded,
                            key: const ValueKey<String>('unselected'),
                            color: tokens.iconSecondary,
                            size: 28,
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

class _PurposeEntrance extends StatelessWidget {
  const _PurposeEntrance({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final duration = CommonUiMotion.layout + delay;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: CommonUiMotion.enter,
      builder: (context, value, child) {
        final adjusted = delay == Duration.zero
            ? value
            : ((value * duration.inMilliseconds - delay.inMilliseconds) /
                    CommonUiMotion.layout.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        return Opacity(
          opacity: adjusted,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - adjusted)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
