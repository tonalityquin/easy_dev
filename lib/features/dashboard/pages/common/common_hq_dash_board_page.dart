import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../account/applications/user_state.dart';
import '../../../calendar/presentation/headquarter_calendar_card.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../headquarter/application/fab/hub_quick_actions.dart';
import '../../widgets/widgets/info/my_info_dialog.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../selector/sheets/service_bottom_sheet.dart';

enum HqDashBoardStylePreset {
  doubleLegacy,
  outlined,
}

typedef HandleWorkStatus = Future<void> Function(
  UserState userState,
  BuildContext context,
);

class CommonHqDashBoardPage extends StatefulWidget {
  const CommonHqDashBoardPage({
    super.key,
    required this.screenName,
    required this.userInfoCard,
    required this.breakButton,
    required this.onHandleWorkStatus,
    required this.stylePreset,
    this.showLogout = true,
    this.showDocumentBox = true,
  });

  final String screenName;
  final Widget userInfoCard;
  final Widget breakButton;
  final HandleWorkStatus onHandleWorkStatus;
  final HqDashBoardStylePreset stylePreset;
  final bool showLogout;
  final bool showDocumentBox;

  @override
  State<CommonHqDashBoardPage> createState() => _CommonHqDashBoardPageState();
}

class _CommonHqDashBoardPageState extends State<CommonHqDashBoardPage> {
  static const int _opsActionPageCount = 3;

  late final PageController _opsActionPageController;
  int _opsActionPageIndex = 0;
  final List<String> _opsDebugLines = <String>[];

  @override
  void initState() {
    super.initState();
    _opsActionPageController = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _opsActionPageController.dispose();
    super.dispose();
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    _trace(
      '로그아웃',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'logout',
      },
    );
    await LogoutHelper.logoutAndGoToLogin(context, useCommonUi: true);
  }

  Future<void> _openServiceSettings(BuildContext context) async {
    _trace(
      '서비스 설정 오픈',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'open_service_settings',
      },
    );

    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    await ServiceBottomSheet.show(
      context: rootCtx,
    );
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    try {
      if (DebugActionRecorder.instance.isRecording) {
        await DebugActionRecorder.instance.stopAndSave(
          titleOverride: 'auto:clockout_exit',
        );
      }
    } catch (_) {}

    await AppExitService.exitApp(context, useCommonUi: true);
  }

  Future<void> _handleClockOutFlow(
    BuildContext context,
    UserState userState,
  ) async {
    _trace(
      '퇴근 처리 시작',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_flow_start',
        'isWorkingBefore': userState.isWorking,
      },
    );

    await widget.onHandleWorkStatus(userState, context);

    if (!mounted) return;

    _trace(
      '퇴근 상태 반영',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_state_updated',
        'isWorkingAfter': userState.isWorking,
      },
    );

    if (!userState.isWorking) {
      final session = userState.session;
      if (session != null) {
        final now = DateTime.now();

        _trace(
          '퇴근 이벤트 기록',
          meta: <String, dynamic>{
            'screen': widget.screenName,
            'action': 'workout_event_insert_and_upload',
            'area': userState.currentArea,
            'division': userState.division,
            'at': now.toIso8601String(),
          },
        );

        await AttBrkRepository.instance.insertEventAndUpload(
          dateTime: now,
          type: AttBrkModeType.workOut,
          userId: session.id,
          userName: session.displayName,
          area: userState.currentArea,
          division: userState.division,
        );
      }

      _trace(
        '앱 종료 진행',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'exit_after_clockout',
        },
      );

      await _exitAppAfterClockOut(context);
    } else {
      _trace(
        '퇴근 처리 미완료',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'clockout_not_completed',
          'reason': 'userState.isWorking_still_true',
        },
      );
    }
  }

  Future<void> _onClockOutPressed(
    BuildContext context,
    UserState userState,
  ) async {
    _trace(
      '퇴근하기 버튼',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'action': 'clockout_tap',
        'isWorking': userState.isWorking,
      },
    );

    if (userState.isWorking) {
      _trace(
        '퇴근 다이얼로그 생략',
        meta: <String, dynamic>{
          'screen': widget.screenName,
          'action': 'clockout_dialog_skipped',
          'reason': 'immediate_clockout_required',
        },
      );
    }

    await _handleClockOutFlow(context, userState);
  }

  Widget _dialogPanel({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

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
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Icon(icon, color: tokens.onAccentContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                    letterSpacing: -.2,
                  ),
                ),
              ),
              CommonIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                haptic: CommonHaptic.selection,
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Future<void> _openWorkActionsDialog(
    BuildContext context,
    UserState userState,
  ) async {
    final tokens = CommonUiTheme.of(context);

    await showCommonDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _dialogPanel(
          context: dialogContext,
          title: '근무 액션',
          icon: Icons.work_history_rounded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: double.infinity, child: widget.breakButton),
              const SizedBox(height: 8),
              _OpsHqActionTile(
                label: '퇴근하기',
                icon: Icons.exit_to_app_rounded,
                color: tokens.danger,
                danger: true,
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _onClockOutPressed(context, userState);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleHeadHubQuickButton() async {
    await HeadHubActions.init();
    HeadHubActions.toggle();
    HapticFeedback.selectionClick();
  }

  Future<void> _openMyInfo(BuildContext context) async {
    await showMyInfoDialog(
      context: context,
      source: MyInfoEntrySource.hqDashboard,
    );
  }

  String _opsDebugMessage({
    required String label,
    required String action,
  }) {
    final now = DateTime.now().toIso8601String();
    return '[HQ_DASHBOARD] timestamp=$now screen=${widget.screenName} '
        'page=${_opsActionPageIndex + 1}/$_opsActionPageCount '
        'label=$label action=$action';
  }

  void _recordOpsDebug(String message) {
    _opsDebugLines.add(message);
    if (_opsDebugLines.length > 120) {
      _opsDebugLines.removeRange(0, _opsDebugLines.length - 120);
    }
    debugPrint(message);
  }

  Future<void> _runOpsAction(
    BuildContext context, {
    required String label,
    required String action,
    required Future<void> Function() operation,
  }) async {
    final message = _opsDebugMessage(label: label, action: action);
    _recordOpsDebug('$message phase=start');
    _trace(
      '본사 대시보드 액션',
      meta: <String, dynamic>{
        'screen': widget.screenName,
        'page': _opsActionPageIndex + 1,
        'label': label,
        'action': action,
      },
    );
    try {
      await operation();
      _recordOpsDebug('$message phase=complete');
    } catch (error, stackTrace) {
      _recordOpsDebug(
        '$message phase=failure error=$error\n'
        'StackTrace:\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> _showOpsDebugStatus(
    BuildContext context, {
    required String label,
    required String action,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted || !context.mounted) return;

    final message = _opsDebugMessage(label: label, action: action);
    _recordOpsDebug('$message phase=status_open');
    final snapshot = List<String>.of(_opsDebugLines);
    final code = snapshot
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
    HapticFeedback.mediumImpact();

    await StatusDialog.showSuccess(
      context,
      title: '개발자 상태',
      description: '$label 액션 디버그 코드를 복사할 수 있습니다.',
      copyText: code,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  String _modeLabel() {
    final screen = widget.screenName.toLowerCase();
    if (screen.contains('minor')) return '확장형';
    if (screen.contains('triple')) return '기본형';
    if (screen.contains('double') || screen.contains('lite')) return '경량형';
    return '경량형';
  }

  String _safe(String value, {String fallback = '-'}) {
    final v = value.trim();
    return v.isEmpty ? fallback : v;
  }

  void _onOpsActionPageChanged(int page) {
    final int logicalPage;
    if (page == 0) {
      logicalPage = _opsActionPageCount - 1;
    } else if (page == _opsActionPageCount + 1) {
      logicalPage = 0;
    } else {
      logicalPage = page - 1;
    }

    if (_opsActionPageIndex != logicalPage) {
      HapticFeedback.selectionClick();
      setState(() {
        _opsActionPageIndex = logicalPage;
      });
    }

    if (page == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_opsActionPageController.hasClients) return;
        _opsActionPageController.jumpToPage(_opsActionPageCount);
      });
      return;
    }

    if (page == _opsActionPageCount + 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_opsActionPageController.hasClients) return;
        _opsActionPageController.jumpToPage(1);
      });
    }
  }

  int _logicalOpsActionPage(int page) {
    if (page == 0) return _opsActionPageCount - 1;
    if (page == _opsActionPageCount + 1) return 0;
    return page - 1;
  }

  Widget _buildOpsActionPage(
    BuildContext context,
    UserState userState,
    int page,
  ) {
    final tokens = CommonUiTheme.of(context);

    switch (page) {
      case 0:
        return Row(
          children: [
            Expanded(
              child: _OpsHqCarouselButton(
                label: '내정보',
                icon: Icons.person_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '내정보',
                  action: 'open_my_info',
                  operation: () => _openMyInfo(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '내정보',
                  action: 'open_my_info',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '근무액션',
                icon: Icons.work_history_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '근무액션',
                  action: 'open_work_actions',
                  operation: () => _openWorkActionsDialog(context, userState),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '근무액션',
                  action: 'open_work_actions',
                ),
              ),
            ),
          ],
        );
      case 1:
        return Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: HeadHubActions.enabled,
                builder: (context, enabled, _) {
                  return _OpsHqCarouselButton(
                    label: '퀵버튼',
                    icon: Icons.lightbulb_rounded,
                    color: enabled ? tokens.warning : tokens.iconDisabled,
                    leading: _OpsHqQuickButtonIndicator(enabled: enabled),
                    onTap: () => _runOpsAction(
                      context,
                      label: '퀵버튼',
                      action: enabled
                          ? 'disable_head_hub_quick_button'
                          : 'enable_head_hub_quick_button',
                      operation: _toggleHeadHubQuickButton,
                    ),
                    onLongPress: () => _showOpsDebugStatus(
                      context,
                      label: '퀵버튼',
                      action: enabled
                          ? 'disable_head_hub_quick_button'
                          : 'enable_head_hub_quick_button',
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '다운받기',
                icon: Icons.download_rounded,
                color: tokens.info,
                onTap: () => _runOpsAction(
                  context,
                  label: '다운받기',
                  action: 'refresh_area_master',
                  operation: () => HeadHubActions.refreshAreaMaster(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '다운받기',
                  action: 'refresh_area_master',
                ),
              ),
            ),
          ],
        );
      case 2:
      default:
        return Row(
          children: [
            Expanded(
              child: _OpsHqCarouselButton(
                label: '환경설정',
                icon: Icons.settings_rounded,
                color: tokens.accent,
                onTap: () => _runOpsAction(
                  context,
                  label: '환경설정',
                  action: 'open_service_settings',
                  operation: () => _openServiceSettings(context),
                ),
                onLongPress: () => _showOpsDebugStatus(
                  context,
                  label: '환경설정',
                  action: 'open_service_settings',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '로그아웃',
                icon: Icons.logout_rounded,
                color: tokens.danger,
                onTap: widget.showLogout
                    ? () => _runOpsAction(
                          context,
                          label: '로그아웃',
                          action: 'logout',
                          operation: () => _handleLogout(context),
                        )
                    : null,
                onLongPress: widget.showLogout
                    ? () => _showOpsDebugStatus(
                          context,
                          label: '로그아웃',
                          action: 'logout',
                        )
                    : null,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildAnimatedOpsActionPage(
    BuildContext context, {
    required int page,
    required Widget child,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    return AnimatedBuilder(
      animation: _opsActionPageController,
      child: child,
      builder: (context, staticChild) {
        var currentPage = 1.0;
        if (_opsActionPageController.hasClients &&
            _opsActionPageController.position.hasContentDimensions) {
          currentPage = _opsActionPageController.page ?? 1.0;
        }
        final distance = (currentPage - page).abs().clamp(0.0, 1.0).toDouble();
        final visibility = 1.0 - distance;
        final opacity = 0.78 + (0.22 * visibility);
        final scale = 0.97 + (0.03 * visibility);
        final offsetY = 5.0 * distance;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offsetY),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: staticChild,
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpsActionCarousel(
    BuildContext context,
    UserState userState,
  ) {
    return Column(
      children: [
        SizedBox(
          height: 60,
          child: PageView.builder(
            controller: _opsActionPageController,
            itemCount: _opsActionPageCount + 2,
            onPageChanged: _onOpsActionPageChanged,
            itemBuilder: (context, page) {
              final child = _buildOpsActionPage(
                context,
                userState,
                _logicalOpsActionPage(page),
              );
              return _buildAnimatedOpsActionPage(
                context,
                page: page,
                child: child,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _OpsHqPageDots(
          count: _opsActionPageCount,
          currentIndex: _opsActionPageIndex,
        ),
      ],
    );
  }

  Widget _buildOpsHeader(
    BuildContext context,
    UserState userState,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final name = _safe(userState.name);
    final position = _safe(userState.position);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.apartment_rounded,
                    color: tokens.onAccentContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '본사 대시보드',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (textTheme.titleLarge ??
                                    const TextStyle(fontSize: 22))
                                .copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OpsHqBadge(
                          label: _modeLabel(),
                          color: tokens.accentContainer,
                          foreground: tokens.onAccentContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _OpsHqHeaderPill(
                            icon: Icons.person_rounded, text: name),
                        _OpsHqHeaderPill(
                            icon: Icons.badge_rounded, text: position),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildOpsActionCarousel(context, userState),
        ],
      ),
    );
  }

  Widget _buildMenuPanel() {
    return const _OpsHqPanel(
      title: '업무 메뉴',
      icon: Icons.dashboard_customize_rounded,
      child: HeadquarterCalendarCard(
        useCommonUi: true,
        showAccountEntry: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: Consumer<UserState>(
          builder: (context, userState, _) {
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 18 + bottomInset),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        CommonAnimatedReveal(
                          child: _buildOpsHeader(context, userState),
                        ),
                        const SizedBox(height: 12),
                        CommonAnimatedReveal(
                          delay: const Duration(milliseconds: 70),
                          child: _buildMenuPanel(),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


class _OpsHqBadge extends StatelessWidget {
  const _OpsHqBadge({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: -.1,
        ),
      ),
    );
  }
}

class _OpsHqHeaderPill extends StatelessWidget {
  const _OpsHqHeaderPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.iconSecondary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpsHqQuickButtonIndicator extends StatefulWidget {
  const _OpsHqQuickButtonIndicator({required this.enabled});

  final bool enabled;

  @override
  State<_OpsHqQuickButtonIndicator> createState() =>
      _OpsHqQuickButtonIndicatorState();
}

class _OpsHqQuickButtonIndicatorState extends State<_OpsHqQuickButtonIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _OpsHqQuickButtonIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      _syncAnimation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.enabled && !reduceMotion) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final value = widget.enabled && !reduceMotion ? _pulse.value : 0.0;
        final color = widget.enabled ? tokens.warning : tokens.iconDisabled;

        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: widget.enabled
                ? tokens.warningContainer
                : tokens.surfaceDisabled,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.enabled
                  ? tokens.warning.withOpacity(.62)
                  : tokens.borderSubtle,
            ),
            boxShadow: widget.enabled
                ? [
                    BoxShadow(
                      color: tokens.warning.withOpacity(.12 + (value * .12)),
                      blurRadius: 6 + (value * 6),
                      spreadRadius: value,
                    ),
                  ]
                : const [],
          ),
          child: Center(
            child: AnimatedScale(
              scale: widget.enabled ? 1 + (value * .08) : 1,
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: Icon(
                  widget.enabled
                      ? Icons.lightbulb_rounded
                      : Icons.lightbulb_outline_rounded,
                  key: ValueKey<bool>(widget.enabled),
                  color: color,
                  size: 19,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OpsHqCarouselButton extends StatefulWidget {
  const _OpsHqCarouselButton({
    required this.label,
    required this.icon,
    required this.color,
    this.leading,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_OpsHqCarouselButton> createState() => _OpsHqCarouselButtonState();
}

class _OpsHqCarouselButtonState extends State<_OpsHqCarouselButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onTap != null;
    final background = !enabled
        ? tokens.surfaceDisabled
        : _pressed || _hovered
            ? tokens.surfaceSelected
            : tokens.surfaceOverlay;
    final foreground = enabled ? tokens.textPrimary : tokens.textDisabled;
    final iconColor = enabled ? widget.color : tokens.iconDisabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        height: 60,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: _focused ? tokens.focusRing : tokens.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _hovered && enabled
              ? [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(_pressed ? .12 : .06),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
                child: Row(
                  children: [
                    widget.leading ??
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: enabled
                                ? widget.color.withOpacity(.14)
                                : tokens.surfaceDisabled,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: enabled
                                  ? widget.color.withOpacity(.34)
                                  : tokens.borderSubtle,
                            ),
                          ),
                          child: Icon(widget.icon, color: iconColor, size: 19),
                        ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.15,
                        ),
                      ),
                    ),
                    if (enabled) ...[
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: tokens.iconSecondary,
                        size: 17,
                      ),
                    ],
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

class _OpsHqPageDots extends StatelessWidget {
  const _OpsHqPageDots({
    required this.count,
    required this.currentIndex,
  });

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.enter,
          width: active ? 8 : 6,
          height: active ? 8 : 6,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? tokens.accent : tokens.borderStrong,
          ),
        );
      }),
    );
  }
}

class _OpsHqPanel extends StatelessWidget {
  const _OpsHqPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow.withOpacity(tokens.isDark ? .22 : .08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tokens.onAccentContainer, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _OpsHqActionTile extends StatefulWidget {
  const _OpsHqActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool danger;

  @override
  State<_OpsHqActionTile> createState() => _OpsHqActionTileState();
}

class _OpsHqActionTileState extends State<_OpsHqActionTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onTap != null;
    final effectiveColor = enabled ? widget.color : tokens.iconDisabled;
    final background = !enabled
        ? tokens.surfaceDisabled
        : _pressed || _hovered
            ? tokens.surfaceSelected
            : tokens.surface;
    final foreground = !enabled
        ? tokens.textDisabled
        : widget.danger
            ? tokens.danger
            : tokens.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: _focused
                ? tokens.focusRing
                : widget.danger
                    ? tokens.danger.withOpacity(enabled ? .52 : .22)
                    : tokens.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _hovered && enabled
              ? [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            overlayColor: WidgetStatePropertyAll(
              effectiveColor.withOpacity(_pressed ? .12 : .06),
            ),
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
            child: SizedBox(
              height: 58,
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(CommonUiShapes.button),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: effectiveColor.withOpacity(.12),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: effectiveColor.withOpacity(.30),
                        ),
                      ),
                      child: Icon(
                        widget.icon,
                        color: effectiveColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -.1,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: enabled
                            ? tokens.iconSecondary
                            : tokens.iconDisabled,
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

enum _DashboardMenuTone {
  primary,
  secondary,
  tertiary,
  neutral,
}

class HqDashBoardButtonStyles {
  static ButtonStyle clockOut(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;

    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.surface,
          foregroundColor: cs.error,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          elevation: 0,
          side: BorderSide(color: cs.error.withOpacity(0.65), width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.error.withOpacity(0.10)
                : null,
          ),
        );

      case HqDashBoardStylePreset.outlined:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.errorContainer,
          foregroundColor: cs.onErrorContainer,
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          elevation: 0,
          side: BorderSide(color: cs.error.withOpacity(0.16), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.error.withOpacity(0.08)
                : null,
          ),
        );
    }
  }

  static ButtonStyle menuTile(
    BuildContext context,
    _DashboardMenuTone tone,
    HqDashBoardStylePreset preset,
  ) {
    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return _legacyMenuTile(context, tone);
      case HqDashBoardStylePreset.outlined:
        return _tonalMenuTile(context, tone);
    }
  }

  static ButtonStyle utilityAccent(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;

    switch (preset) {
      case HqDashBoardStylePreset.doubleLegacy:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.surface,
          foregroundColor: cs.primary,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          side: BorderSide(color: cs.primary.withOpacity(0.75), width: 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.primary.withOpacity(0.08)
                : null,
          ),
        );

      case HqDashBoardStylePreset.outlined:
        return ElevatedButton.styleFrom(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          side: BorderSide(color: cs.primary.withOpacity(0.14), width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
            (states) => states.contains(MaterialState.pressed)
                ? cs.primary.withOpacity(0.08)
                : null,
          ),
        );
    }
  }

  static ButtonStyle utilityNeutral(
    BuildContext context,
    HqDashBoardStylePreset preset,
  ) {
    final cs = Theme.of(context).colorScheme;
    final overlay = preset == HqDashBoardStylePreset.doubleLegacy ? 0.14 : 0.10;
    final borderOpacity =
        preset == HqDashBoardStylePreset.doubleLegacy ? 0.24 : 0.18;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      side: BorderSide(color: cs.outline.withOpacity(borderOpacity), width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? cs.onSurface.withOpacity(overlay)
            : null,
      ),
    );
  }

  static ButtonStyle _legacyMenuTile(
    BuildContext context,
    _DashboardMenuTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;

    late final Color fg;
    late final Color border;

    switch (tone) {
      case _DashboardMenuTone.primary:
        fg = cs.primary;
        border = cs.primary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.secondary:
        fg = cs.secondary;
        border = cs.secondary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.tertiary:
        fg = cs.tertiary;
        border = cs.tertiary.withOpacity(0.35);
        break;
      case _DashboardMenuTone.neutral:
        fg = cs.onSurface;
        border = cs.outline.withOpacity(0.20);
        break;
    }

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: fg,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      side: BorderSide(color: border, width: 1.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? fg.withOpacity(0.08)
            : null,
      ),
    );
  }

  static ButtonStyle _tonalMenuTile(
    BuildContext context,
    _DashboardMenuTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color fg;

    switch (tone) {
      case _DashboardMenuTone.primary:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        break;
      case _DashboardMenuTone.secondary:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case _DashboardMenuTone.tertiary:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        break;
      case _DashboardMenuTone.neutral:
        bg = cs.surfaceVariant;
        fg = cs.onSurfaceVariant;
        break;
    }

    return ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: fg,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      side: BorderSide(color: fg.withOpacity(0.10), width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? fg.withOpacity(0.08)
            : null,
      ),
    );
  }
}
