import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/models/capability.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../account/applications/user_state.dart';
import '../../../calendar/presentation/headquarter_calendar_card.dart';
import '../../../chat/application/chat_area_key.dart';
import '../../../chat/presentation/area_chat_inbox_scope.dart';
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
    await LogoutHelper.logoutAndGoToLogin(context);
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

    await AppExitService.exitApp(context);
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        letterSpacing: -.2,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettingsActionsDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final children = <Widget>[
          _OpsHqActionTile(
            label: '설정',
            icon: Icons.settings_rounded,
            color: cs.primary,
            onTap: () {
              Navigator.of(dialogContext).pop();
              _openServiceSettings(context);
            },
          ),
        ];

        if (widget.showLogout) {
          children.add(const SizedBox(height: 8));
          children.add(
            _OpsHqActionTile(
              label: '로그아웃',
              icon: Icons.logout_rounded,
              color: cs.error,
              danger: true,
              onTap: () {
                Navigator.of(dialogContext).pop();
                _handleLogout(context);
              },
            ),
          );
        }

        return _dialogPanel(
          context: dialogContext,
          title: '설정 및 계정',
          icon: Icons.manage_accounts_rounded,
          child: Column(children: children),
        );
      },
    );
  }

  Future<void> _openWorkActionsDialog(
    BuildContext context,
    UserState userState,
  ) async {
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
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
                color: cs.error,
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

  Future<void> _openHeadHubQuickActionsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final tt = Theme.of(dialogContext).textTheme;

        return _dialogPanel(
          context: dialogContext,
          title: '본사 퀵 버튼',
          icon: Icons.bolt_rounded,
          child: ValueListenableBuilder<bool>(
            valueListenable: HeadHubActions.enabled,
            builder: (context, on, _) {
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.70)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: on ? cs.primary : cs.surface,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: on ? cs.primary : cs.outlineVariant,
                        ),
                      ),
                      child: Icon(
                        on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: on ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            on ? '빠른 실행 ON' : '빠른 실행 OFF',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '본사 허브 퀵 버튼 활성화 여부를 선택합니다.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch.adaptive(
                      value: on,
                      onChanged: (value) async {
                        HeadHubActions.setEnabled(value);
                        if (value) {
                          await HeadHubActions.mountIfNeeded();
                        }
                        HapticFeedback.selectionClick();
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
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

  String _roleLabel(UserState userState) {
    final raw = userState.session?.role;
    final role = raw == null ? '' : raw.toString().trim();
    return role.isEmpty ? '-' : role;
  }

  String _workLabel(UserState userState) {
    return userState.isWorking ? '근무중' : '대기';
  }

  Widget _buildOpsHeader(
    BuildContext context,
    UserState userState,
    int menuCount,
  ) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = _safe(userState.name);
    final position = _safe(userState.position);
    final division = _safe(userState.division);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(.42)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.08),
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
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.apartment_rounded, color: cs.onPrimary),
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
                            style: (textTheme.titleLarge ?? const TextStyle(fontSize: 22)).copyWith(
                              color: cs.onInverseSurface,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _OpsHqBadge(
                          label: _modeLabel(),
                          color: cs.primary,
                          foreground: cs.onPrimary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _OpsHqHeaderPill(icon: Icons.person_rounded, text: name),
                        _OpsHqHeaderPill(icon: Icons.badge_rounded, text: position),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _OpsHqMetric(
                  label: '설정',
                  value: '열기',
                  icon: Icons.settings_rounded,
                  color: cs.primary,
                  onTap: () => _openSettingsActionsDialog(context),
                ),
                const SizedBox(width: 8),
                _OpsHqMetric(
                  label: '근무',
                  value: _workLabel(userState),
                  icon: Icons.timer_rounded,
                  color: userState.isWorking ? cs.primary : cs.onInverseSurface,
                  onTap: () => _openWorkActionsDialog(context, userState),
                ),
                const SizedBox(width: 8),
                _OpsHqMetric(
                  label: '본부',
                  value: division,
                  icon: Icons.domain_rounded,
                  color: cs.tertiary,
                  onTap: () => _openHeadHubQuickActionsDialog(context),
                ),
                const SizedBox(width: 8),
                _OpsHqMetric(label: '메뉴', value: '$menuCount', icon: Icons.grid_view_rounded, color: cs.primary),
                const SizedBox(width: 8),
                _OpsHqMetric(label: '권한', value: _roleLabel(userState), icon: Icons.verified_user_rounded, color: cs.secondary),
              ],
            ),
          ),
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceVariant.withOpacity(.20),
      body: SafeArea(
        child: Consumer<UserState>(
          builder: (context, userState, _) {
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        _buildOpsHeader(context, userState, 1),
                        const SizedBox(height: 12),
                        _buildMenuPanel(context, userState),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AreaChatInboxScope(
      areaNames: const <String>[headquarterChatAreaName],
      notificationsEnabled: false,
      builder: (context, inbox, currentUserId) {
        final unreadCount = inbox.unreadCountForArea(
          headquarterChatAreaName,
          currentUserId,
        );
        return _HeadquarterChatFabVisual(
          unreadCount: unreadCount,
          onPressed: () => _openChat(context),
        );
      },
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
    final cs = Theme.of(context).colorScheme;
    final active = unreadCount > 0;
    final color = cs.primary;

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
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
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
                      color: cs.error,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: cs.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: TextStyle(
                        color: cs.onError,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.onInverseSurface.withOpacity(.82)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onInverseSurface.withOpacity(.88),
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

class _OpsHqMetric extends StatelessWidget {
  const _OpsHqMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = Container(
      width: 112,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(onTap == null ? .08 : .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onInverseSurface.withOpacity(onTap == null ? .12 : .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onInverseSurface.withOpacity(.62),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.1,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onInverseSurface.withOpacity(.70),
              size: 18,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      label: '$label 열기',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: content,
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.70)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
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
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: cs.onPrimaryContainer, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
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

class _OpsHqActionTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final effectiveColor = enabled ? color : cs.onSurfaceVariant.withOpacity(.45);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          height: 58,
          decoration: BoxDecoration(
            color: enabled ? cs.surface : cs.surfaceVariant.withOpacity(.28),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: danger
                  ? cs.error.withOpacity(enabled ? .45 : .20)
                  : cs.outlineVariant.withOpacity(.70),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: effectiveColor,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(15)),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: effectiveColor.withOpacity(.12),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: effectiveColor.withOpacity(.20)),
                ),
                child: Icon(icon, color: effectiveColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? (danger ? cs.error : cs.onSurface) : cs.onSurfaceVariant.withOpacity(.55),
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
                  color: enabled ? cs.onSurfaceVariant.withOpacity(.75) : cs.onSurfaceVariant.withOpacity(.35),
                ),
              ),
            ],
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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final statusLabel = _expanded ? '접기' : '펼치기';
    final statusIcon = _expanded
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;

    return Semantics(
      button: true,
      label: '지사 별 업무 현황 $statusLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleExpanded,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: cs.inverseSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(.5),
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _expanded ? cs.primaryContainer : cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.domain_rounded,
                    color: _expanded
                        ? cs.onPrimaryContainer
                        : cs.onPrimary,
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
                        style: (tt.titleMedium ??
                                const TextStyle(fontSize: 16))
                            .copyWith(
                          fontWeight: FontWeight.w900,
                          color: cs.onInverseSurface,
                          letterSpacing: -.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '마스터 ${_formatAreaMasterRefreshAt(_areaMasterRefreshedAtIso)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onInverseSurface.withOpacity(.72),
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
                    color: cs.onInverseSurface.withOpacity(.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: cs.onInverseSurface.withOpacity(.22),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: child,
                      );
                    },
                    child: Icon(
                      statusIcon,
                      key: ValueKey<bool>(_expanded),
                      size: 22,
                      color: cs.onInverseSurface,
                    ),
                  ),
                ),
              ],
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
        description: '빠른 실행에서 지역 마스터 갱신을 실행하세요.',
      );
    }

    final chatAreaNames = data.areaCounts
        .where((item) => item.chatEnabled)
        .map((item) => item.areaName)
        .toList(growable: false);

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
                child: AreaChatInboxScope(
                  areaNames: chatAreaNames,
                  notificationsEnabled: false,
                  builder: (context, inbox, currentUserId) {
                    return Column(
                      children: data.areaCounts
                          .map(
                            (item) => _BranchAreaMiniCard(
                              item: item,
                              unreadCount: item.chatEnabled
                                  ? inbox.unreadCountForArea(
                                      item.areaName,
                                      currentUserId,
                                    )
                                  : 0,
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
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
        const HeadquarterCalendarCard(),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onInverseSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ).copyWith(color: cs.onInverseSurface),
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
                child: Icon(Icons.domain_rounded, color: cs.onPrimaryContainer, size: 18),
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
    final color = allowed
        ? Colors.green.shade700
        : Colors.red.shade700;

    return Semantics(
      label: label,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(.50)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              allowed
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
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
                  style: (tt.titleMedium ??
                          const TextStyle(fontSize: 16))
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

  List<String> get visibleModes => modes
      .where((mode) => mode != 'record')
      .toList(growable: false);
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
  }) async {
    final area = areaName.trim();
    if (area.isEmpty) return;
    await AreaChatPanel.showSheet(
      context: context,
      areaName: area,
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
    required this.unreadCount,
  });

  final _BranchWorkStatusAreaCount item;
  final int unreadCount;

  Future<void> _openChat(BuildContext context) async {
    if (!item.chatEnabled) return;
    final area = item.areaName.trim();
    if (area.isEmpty) return;
    await _AreaChatReadOpenHelper.open(
      context: context,
      areaName: area,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

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
                onPressed: item.chatEnabled
                    ? () => _openChat(context)
                    : null,
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
    final cs = Theme.of(context).colorScheme;
    final color = allowed ? Colors.green.shade700 : Colors.red.shade700;
    final background = Color.alphaBlend(
      color.withOpacity(allowed ? .12 : .10),
      cs.surface,
    );
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
