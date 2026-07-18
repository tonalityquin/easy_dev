import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/models/capability.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../account/applications/user_state.dart';
import '../../../calendar/presentation/headquarter_calendar_card.dart';
import '../../../chat/application/chat_account_scope.dart';
import '../../../chat/application/chat_area_key.dart';
import '../../../chat/controllers/area_chat_inbox_controller.dart';
import '../../../chat/presentation/area_chat_icon_button.dart';
import '../../../chat/presentation/area_chat_panel.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../headquarter/application/area/area_master_cache.dart';
import '../../../headquarter/application/fab/hub_quick_actions.dart';
import '../../../mode_single/application/att_brk_repository.dart';
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
    await LogoutHelper.logoutAndGoToLogin(context, usePromptUi: true);
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

    await AppExitService.exitApp(context, usePromptUi: true);
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
    final tokens = PromptUiTheme.of(context);
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
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
              PromptIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
                haptic: PromptHaptic.selection,
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
    final tokens = PromptUiTheme.of(context);

    await showPromptDialog<void>(
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
    final tokens = PromptUiTheme.of(context);

    switch (page) {
      case 0:
        return Row(
          children: [
            Expanded(
              child: _OpsHqCarouselButton(
                label: '환경설정',
                icon: Icons.settings_rounded,
                color: tokens.accent,
                onTap: () => _openServiceSettings(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '근무액션',
                icon: Icons.work_history_rounded,
                color: tokens.info,
                onTap: () => _openWorkActionsDialog(context, userState),
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
                    onTap: _toggleHeadHubQuickButton,
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
                onTap: () => HeadHubActions.refreshAreaMaster(context),
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
                label: '로그아웃',
                icon: Icons.logout_rounded,
                color: tokens.danger,
                onTap: widget.showLogout ? () => _handleLogout(context) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OpsHqCarouselButton(
                label: '가이드북',
                icon: Icons.menu_book_rounded,
                color: tokens.info,
              ),
            ),
          ],
        );
    }
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
              return _buildOpsActionPage(
                context,
                userState,
                _logicalOpsActionPage(page),
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
    final tokens = PromptUiTheme.of(context);
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
                child: Icon(Icons.apartment_rounded, color: tokens.onAccentContainer),
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

  Widget _buildMenuPanel(BuildContext context, UserState userState) {
    return _OpsHqPanel(
      title: '업무 메뉴',
      icon: Icons.dashboard_customize_rounded,
      child: _BranchWorkStatusInlinePanel(
        screenName: widget.screenName,
        division: userState.division.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
                        PromptAnimatedReveal(
                          child: _buildOpsHeader(context, userState),
                        ),
                        const SizedBox(height: 12),
                        PromptAnimatedReveal(
                          delay: const Duration(milliseconds: 70),
                          child: _buildMenuPanel(context, userState),
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
      floatingActionButton: const _HeadquarterChatFloatingButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _HeadquarterChatFloatingButton extends StatelessWidget {
  const _HeadquarterChatFloatingButton();

  Future<void> _openChat(BuildContext context) async {
    await _AreaChatReadOpenHelper.open(
      context: context,
      areaName: headquarterChatAreaName,
      usePromptUi: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.select<UserState, String>(
      (state) => ChatAccountScope.fromSession(state.session).userId,
    );
    final unreadCount = context.select<AreaChatInboxController, int>(
      (controller) => controller.snapshot.unreadCountForArea(
        headquarterChatAreaName,
        currentUserId,
      ),
    );
    return _HeadquarterChatFabVisual(
      unreadCount: unreadCount,
      onPressed: () => _openChat(context),
    );
  }
}

class _HeadquarterChatFabVisual extends StatelessWidget {
  const _HeadquarterChatFabVisual({
    required this.unreadCount,
    required this.onPressed,
  });

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final active = unreadCount > 0;
    final color = tokens.accent;

    return Tooltip(
      message: '본사 채팅 열기',
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(active ? .28 : .18),
                    blurRadius: active ? 18 : 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: FloatingActionButton(
                heroTag: 'headquarter_chat_fab',
                tooltip: '본사 채팅',
                backgroundColor: tokens.accentContainer,
                foregroundColor: tokens.onAccentContainer,
                elevation: active ? 8 : 5,
                onPressed: onPressed,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    active
                        ? Icons.mark_chat_unread_rounded
                        : Icons.chat_bubble_outline_rounded,
                    key: ValueKey<bool>(active),
                  ),
                ),
              ),
            ),
            if (active)
              Positioned(
                right: 0,
                top: 0,
                child: AnimatedScale(
                  scale: active ? 1 : .85,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: tokens.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: TextStyle(
                        color: tokens.onDanger,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
    final tokens = PromptUiTheme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final value = widget.enabled && !reduceMotion ? _pulse.value : 0.0;
        final color = widget.enabled ? tokens.warning : tokens.iconDisabled;

        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          curve: PromptUiMotion.standard,
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
              duration:
                  reduceMotion ? Duration.zero : PromptUiMotion.selection,
              curve: PromptUiMotion.enter,
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.selection,
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
  });

  final String label;
  final IconData icon;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  State<_OpsHqCarouselButton> createState() => _OpsHqCarouselButtonState();
}

class _OpsHqCarouselButtonState extends State<_OpsHqCarouselButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        height: 60,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(_pressed ? .12 : .06),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          curve: PromptUiMotion.enter,
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
    final tokens = PromptUiTheme.of(context);
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
    final tokens = PromptUiTheme.of(context);
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
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            child: SizedBox(
              height: 58,
              child: AnimatedScale(
                scale: _pressed && enabled ? .98 : 1,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: effectiveColor,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(PromptUiShapes.button),
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

class _BranchWorkStatusInlinePanel extends StatefulWidget {
  const _BranchWorkStatusInlinePanel({
    required this.screenName,
    required this.division,
  });

  final String screenName;
  final String division;

  @override
  State<_BranchWorkStatusInlinePanel> createState() =>
      _BranchWorkStatusInlinePanelState();
}

class _BranchWorkStatusInlinePanelState
    extends State<_BranchWorkStatusInlinePanel> {
  Future<_BranchWorkStatusViewData>? _future;
  bool _hasRequestedLoad = false;
  bool _isRefreshingAggregations = false;
  bool _expanded = false;
  int _cachedAreaCount = 0;
  String _areaMasterRefreshedAtIso = '';

  @override
  void initState() {
    super.initState();
    _restoreAreaMasterMeta();
  }

  @override
  void didUpdateWidget(covariant _BranchWorkStatusInlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.division != widget.division) {
      _future = null;
      _hasRequestedLoad = false;
      _expanded = false;
      _cachedAreaCount = 0;
      _areaMasterRefreshedAtIso = '';
      _restoreAreaMasterMeta();
    }
  }

  List<AreaMasterItem> _filterBranchItems({
    required List<AreaMasterItem> items,
    required String division,
  }) {
    final normalizedDivision = division.trim();
    final byName = <String, AreaMasterItem>{};

    for (final item in items) {
      final name = item.name.trim();
      if (name.isEmpty) continue;
      if (item.isHeadquarter) continue;
      if (name == normalizedDivision) continue;
      byName[name] = item;
    }

    final filtered = byName.values.toList(growable: false);
    filtered.sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  Future<void> _restoreAreaMasterMeta() async {
    final division = widget.division.trim();
    if (division.isEmpty) return;

    final snapshot = await AreaMasterCache.readSnapshot(division);
    final branchItems = snapshot == null
        ? const <AreaMasterItem>[]
        : _filterBranchItems(
            items: snapshot.items,
            division: division,
          );

    if (!mounted) return;

    setState(() {
      _cachedAreaCount = branchItems.length;
      _areaMasterRefreshedAtIso = snapshot?.refreshedAtIso ?? '';
    });
  }

  Future<int> _countPlates({
    required String area,
    required PlateType plateType,
  }) async {
    final plateRepository = context.read<PlateRepository>();
    return plateRepository.countPlatesByAreaAndType(
      area: area,
      plateType: plateType,
    );
  }

  Future<_BranchWorkStatusAreaCount> _buildAreaCount(
    AreaMasterItem item,
  ) async {
    final results = await Future.wait<int>([
      _countPlates(
        area: item.name,
        plateType: PlateType.parkingCompleted,
      ),
      _countPlates(
        area: item.name,
        plateType: PlateType.departureCompleted,
      ),
    ]);

    final normalizedModes = item.modes
        .map((mode) => mode.trim().toLowerCase())
        .where((mode) => mode.isNotEmpty)
        .toSet()
        .toList(growable: false);
    normalizedModes.sort();

    return _BranchWorkStatusAreaCount(
      areaName: item.name.trim(),
      parkingCompletedCount: results[0],
      departureCompletedCount: results[1],
      modes: List<String>.unmodifiable(normalizedModes),
      capabilities: Set<Capability>.unmodifiable(item.capabilities),
    );
  }

  Future<_BranchWorkStatusViewData> _load() async {
    final division = widget.division.trim();

    if (division.isEmpty) {
      return const _BranchWorkStatusViewData(
        division: '',
        areaCounts: <_BranchWorkStatusAreaCount>[],
        hasAreaMasterCache: false,
        areaMasterRefreshedAtIso: '',
      );
    }

    final snapshot = await AreaMasterCache.readSnapshot(division);
    if (snapshot == null) {
      return _BranchWorkStatusViewData(
        division: division,
        areaCounts: const <_BranchWorkStatusAreaCount>[],
        hasAreaMasterCache: false,
        areaMasterRefreshedAtIso: '',
      );
    }

    final branchItems = _filterBranchItems(
      items: snapshot.items,
      division: division,
    );

    final areaCounts = await Future.wait<_BranchWorkStatusAreaCount>(
      branchItems.map(_buildAreaCount),
    );

    return _BranchWorkStatusViewData(
      division: division,
      areaCounts: areaCounts,
      hasAreaMasterCache: true,
      areaMasterRefreshedAtIso: snapshot.refreshedAtIso,
    );
  }

  Future<_BranchWorkStatusViewData> _loadAndSyncMeta() async {
    final data = await _load();
    if (!mounted) return data;
    setState(() {
      _cachedAreaCount = data.areaCounts.length;
      _areaMasterRefreshedAtIso = data.areaMasterRefreshedAtIso;
    });
    return data;
  }

  void _toggleExpanded() {
    final next = !_expanded;
    setState(() {
      _expanded = next;
      if (next) {
        _hasRequestedLoad = true;
        _future = _loadAndSyncMeta();
      }
    });
    HapticFeedback.selectionClick();
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() {
      _expanded = false;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _refreshAggregations() async {
    if (_isRefreshingAggregations) return;

    final nextFuture = _loadAndSyncMeta();

    setState(() {
      _expanded = true;
      _hasRequestedLoad = true;
      _isRefreshingAggregations = true;
      _future = nextFuture;
    });

    try {
      await nextFuture;
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshingAggregations = false;
      });
    }
  }

  Widget _buildTopBar(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final statusLabel = _expanded ? '접기' : '펼치기';
    final statusIcon = _expanded
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;

    return Semantics(
      button: true,
      label: '지사 별 업무 현황 $statusLabel',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: _expanded ? tokens.surfaceSelected : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          border: Border.all(
            color: _expanded ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(PromptUiShapes.card),
            overlayColor: WidgetStatePropertyAll(
              tokens.accent.withOpacity(.08),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : PromptUiMotion.selection,
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _expanded
                          ? tokens.accent
                          : tokens.accentContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.domain_rounded,
                      color: _expanded
                          ? tokens.onAccent
                          : tokens.onAccentContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '지사 별 업무 현황',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (textTheme.titleMedium ??
                                  const TextStyle(fontSize: 16))
                              .copyWith(
                            fontWeight: FontWeight.w900,
                            color: tokens.textPrimary,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '마스터 ${_formatAreaMasterRefreshAt(_areaMasterRefreshedAtIso)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BranchHeaderPill(
                    icon: Icons.sd_storage_rounded,
                    label: '$_cachedAreaCount',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.pill),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : PromptUiMotion.selection,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        statusIcon,
                        key: ValueKey<bool>(_expanded),
                        size: 22,
                        color: tokens.iconSecondary,
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

  Widget _buildLoadingState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.sync_rounded,
        label: '업무 현황을 불러오는 중입니다.',
        loading: true,
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.error_outline_rounded,
        label: '업무 현황을 불러오지 못했습니다.',
        description: '집계 갱신을 다시 실행하세요.',
      ),
    );
  }

  Widget _buildEmptyDivisionState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.badge_outlined,
        label: 'division 정보가 없습니다.',
      ),
    );
  }

  Widget _buildLoadedState(
    BuildContext context,
    _BranchWorkStatusViewData data,
  ) {
    if (!data.hasAreaMasterCache) {
      return const _BranchStateCard(
        icon: Icons.cloud_download_outlined,
        label: '저장된 지역 마스터가 없습니다.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BranchCapabilityLegend(),
        const SizedBox(height: 12),
        data.areaCounts.isEmpty
            ? const _BranchStateCard(
                icon: Icons.location_off_rounded,
                label: '표시할 지사 지역이 없습니다.',
              )
            : _BranchSectionFrame(
                title: '지사',
                child: Column(
                  children: data.areaCounts
                      .map(
                        (item) => _BranchAreaMiniCard(
                          item: item,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_hasRequestedLoad || _future == null) {
      return const _BranchGuideCard();
    }

    return FutureBuilder<_BranchWorkStatusViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildLoadingState(context);
        }

        if (snapshot.hasError) {
          return _buildErrorState(context);
        }

        final data = snapshot.data ??
            const _BranchWorkStatusViewData(
              division: '',
              areaCounts: <_BranchWorkStatusAreaCount>[],
              hasAreaMasterCache: false,
              areaMasterRefreshedAtIso: '',
            );

        if (data.division.isEmpty) {
          return _buildEmptyDivisionState(context);
        }

        return _buildLoadedState(context, data);
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = !_isRefreshingAggregations;

    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: '지역별 주차·출차 집계 갱신',
        child: Tooltip(
          message: '집계 갱신',
          child: Material(
            color: Color.alphaBlend(
              cs.secondary.withOpacity(.10),
              cs.surface,
            ),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: enabled ? _refreshAggregations : null,
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: _isRefreshingAggregations
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: cs.secondary,
                          ),
                        )
                      : Icon(
                          Icons.sync_rounded,
                          size: 20,
                          color: cs.secondary,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapseButton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _collapse,
        icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
        label: const Text('접기'),
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _expanded
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: KeyedSubtree(
                      key: ValueKey<Future<_BranchWorkStatusViewData>?>(
                        _future,
                      ),
                      child: _buildBody(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildActions(context),
                  const SizedBox(height: 2),
                  _buildCollapseButton(context),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(context),
        _buildExpandedContent(context),
        const SizedBox(height: 12),
        const HeadquarterCalendarCard(usePromptUi: true),
      ],
    );
  }
}

class _BranchHeaderPill extends StatelessWidget {
  const _BranchHeaderPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tokens.iconSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: tokens.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSectionFrame extends StatelessWidget {
  const _BranchSectionFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.domain_rounded,
                    color: cs.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _BranchCapabilityLegend extends StatelessWidget {
  const _BranchCapabilityLegend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(.55),
        ),
      ),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final capability in _capabilityDisplayOrder)
            _BranchCapabilityLegendItem(
              icon: _capabilityIcon(capability),
              label: capability.label,
            ),
          const _BranchCapabilityStateLegend(
            allowed: true,
            label: '허용',
          ),
          const _BranchCapabilityStateLegend(
            allowed: false,
            label: '비허용',
          ),
        ],
      ),
    );
  }
}

class _BranchCapabilityLegendItem extends StatelessWidget {
  const _BranchCapabilityLegendItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: label,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.62),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchCapabilityStateLegend extends StatelessWidget {
  const _BranchCapabilityStateLegend({
    required this.allowed,
    required this.label,
  });

  final bool allowed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final color = allowed ? tokens.success : tokens.danger;
    final background =
        allowed ? tokens.successContainer : tokens.dangerContainer;

    return Semantics(
      label: label,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(.50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchGuideCard extends StatelessWidget {
  const _BranchGuideCard();

  @override
  Widget build(BuildContext context) {
    return const _BranchCapabilityLegend();
  }
}

class _BranchStateCard extends StatelessWidget {
  const _BranchStateCard({
    required this.icon,
    required this.label,
    this.description,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : Icon(icon, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (tt.titleMedium ?? const TextStyle(fontSize: 16))
                      .copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchWorkStatusViewData {
  const _BranchWorkStatusViewData({
    required this.division,
    required this.areaCounts,
    required this.hasAreaMasterCache,
    required this.areaMasterRefreshedAtIso,
  });

  final String division;
  final List<_BranchWorkStatusAreaCount> areaCounts;
  final bool hasAreaMasterCache;
  final String areaMasterRefreshedAtIso;
}

class _BranchWorkStatusAreaCount {
  const _BranchWorkStatusAreaCount({
    required this.areaName,
    required this.parkingCompletedCount,
    required this.departureCompletedCount,
    required this.modes,
    required this.capabilities,
  });

  final String areaName;
  final int parkingCompletedCount;
  final int departureCompletedCount;
  final List<String> modes;
  final CapSet capabilities;

  bool get chatEnabled => capabilities.contains(Capability.record);

  List<String> get visibleModes =>
      modes.where((mode) => mode != 'record').toList(growable: false);
}

String _formatAreaMasterRefreshAt(String iso) {
  final raw = iso.trim();
  if (raw.isEmpty) return '-';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return '-';
  final local = parsed.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month.$day $hour:$minute';
}

class _AreaChatReadOpenHelper {
  const _AreaChatReadOpenHelper._();

  static Future<void> open({
    required BuildContext context,
    required String areaName,
    bool usePromptUi = true,
  }) async {
    final area = areaName.trim();
    if (area.isEmpty) return;
    await AreaChatPanel.showSheet(
      context: context,
      areaName: area,
      usePromptUi: usePromptUi,
    );
  }
}

const List<Capability> _capabilityDisplayOrder = <Capability>[
  Capability.location,
  Capability.tablet,
  Capability.monthly,
  Capability.bill,
  Capability.record,
];

IconData _capabilityIcon(Capability capability) {
  switch (capability) {
    case Capability.location:
      return Icons.location_on_rounded;
    case Capability.tablet:
      return Icons.tablet_mac_rounded;
    case Capability.monthly:
      return Icons.calendar_month_rounded;
    case Capability.bill:
      return Icons.receipt_long_rounded;
    case Capability.record:
      return Icons.record_voice_over_rounded;
  }
}

IconData _modeIcon(String mode) {
  switch (mode.trim().toLowerCase()) {
    case 'single':
      return Icons.looks_one_rounded;
    case 'double':
      return Icons.filter_2_rounded;
    case 'triple':
      return Icons.filter_3_rounded;
    case 'minor':
      return Icons.account_tree_rounded;
    default:
      return Icons.extension_rounded;
  }
}

String _modeLabel(String mode) {
  switch (mode.trim().toLowerCase()) {
    case 'single':
      return '싱글 모드';
    case 'double':
      return '더블 모드';
    case 'triple':
      return '트리플 모드';
    case 'minor':
      return '마이너 모드';
    default:
      return mode.trim();
  }
}

class _BranchAreaMiniCard extends StatelessWidget {
  const _BranchAreaMiniCard({
    required this.item,
  });

  final _BranchWorkStatusAreaCount item;

  Future<void> _openChat(BuildContext context) async {
    if (!item.chatEnabled) return;
    final area = item.areaName.trim();
    if (area.isEmpty) return;
    await _AreaChatReadOpenHelper.open(
      context: context,
      areaName: area,
      usePromptUi: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final currentUserId = context.select<UserState, String>(
      (state) => ChatAccountScope.fromSession(state.session).userId,
    );
    final unreadCount = context.select<AreaChatInboxController, int>(
      (controller) => item.chatEnabled
          ? controller.snapshot.unreadCountForArea(
              item.areaName,
              currentUserId,
            )
          : 0,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.store_mall_directory_rounded,
                  size: 18,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.areaName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              AreaChatIconButton(
                areaName: item.areaName,
                unreadCount: item.chatEnabled ? unreadCount : 0,
                onPressed: item.chatEnabled ? () => _openChat(context) : null,
                disabledTooltip: '채팅 비허용 · 채팅&무전기 기능이 허용되지 않았습니다.',
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _BranchAreaValueChip(
                  icon: Icons.local_parking_rounded,
                  value: '${item.parkingCompletedCount}',
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BranchAreaValueChip(
                  icon: Icons.exit_to_app_rounded,
                  value: '${item.departureCompletedCount}',
                  color: cs.tertiary,
                ),
              ),
            ],
          ),
          if (item.visibleModes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: item.visibleModes
                  .map(
                    (mode) => _AllowedModeIcon(
                      icon: _modeIcon(mode),
                      label: _modeLabel(mode),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: _capabilityDisplayOrder
                .map(
                  (capability) => _CapabilityStatusIcon(
                    icon: _capabilityIcon(capability),
                    label: capability.label,
                    allowed: item.capabilities.contains(capability),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _AllowedModeIcon extends StatelessWidget {
  const _AllowedModeIcon({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      label: '$label 허용',
      child: Tooltip(
        message: '$label · 허용',
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withOpacity(.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: cs.primary.withOpacity(.30),
            ),
          ),
          child: Icon(
            icon,
            size: 16,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _CapabilityStatusIcon extends StatelessWidget {
  const _CapabilityStatusIcon({
    required this.icon,
    required this.label,
    required this.allowed,
  });

  final IconData icon;
  final String label;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final color = allowed ? tokens.success : tokens.danger;
    final background =
        allowed ? tokens.successContainer : tokens.dangerContainer;
    final status = allowed ? '허용' : '비허용';

    return Semantics(
      label: '$label $status',
      child: Tooltip(
        message: '$label · $status',
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withOpacity(.55),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: color,
              ),
              if (!allowed)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchAreaValueChip extends StatelessWidget {
  const _BranchAreaValueChip({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(.10), cs.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
