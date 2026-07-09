import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../account/applications/user_state.dart';
import '../../../chat/presentation/area_chat_inbox_scope.dart';
import '../../../chat/presentation/area_chat_icon_button.dart';
import '../../../chat/presentation/area_chat_panel.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../dev/domain/repositories/area_repo_package/area_repository.dart';
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
  bool _isRefreshingAreas = false;
  bool _isRefreshingAggregations = false;
  int _cachedAreaCount = 0;
  String _lastAreaRefreshDay = '';

  @override
  void initState() {
    super.initState();
    _restoreLocalMeta();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadInitial();
    });
  }

  @override
  void didUpdateWidget(covariant _BranchWorkStatusInlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.division != widget.division) {
      _future = null;
      _hasRequestedLoad = false;
      _cachedAreaCount = 0;
      _lastAreaRefreshDay = '';
      _restoreLocalMeta();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadInitial();
      });
    }
  }

  String _areasCacheKey(String division) => 'branch_areas_$division';

  String _areasRefreshDateKey(String division) =>
      'branch_areas_last_refresh_date_$division';

  String _dayStamp(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get _todayStamp => _dayStamp(DateTime.now());

  bool get _areaRefreshLockedToday => _lastAreaRefreshDay == _todayStamp;

  Future<void> _restoreLocalMeta() async {
    final division = widget.division.trim();
    if (division.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final cached =
        prefs.getStringList(_areasCacheKey(division)) ?? const <String>[];
    final lastRefresh = prefs.getString(_areasRefreshDateKey(division)) ?? '';

    if (!mounted) return;

    setState(() {
      _cachedAreaCount = _filterBranchAreas(
        areaNames: cached,
        division: division,
      ).length;
      _lastAreaRefreshDay = lastRefresh;
    });
  }

  Future<void> _writeLastAreaRefreshDay(String division, String day) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_areasRefreshDateKey(division), day);
  }

  void _syncMetaFromAreas({
    required String division,
    required List<String> areaNames,
    String? refreshedDay,
  }) {
    if (!mounted) return;
    setState(() {
      _cachedAreaCount = _filterBranchAreas(
        areaNames: areaNames,
        division: division,
      ).length;
      if (refreshedDay != null) {
        _lastAreaRefreshDay = refreshedDay;
      }
    });
  }

  String _cacheCountText() => _cachedAreaCount > 0 ? '$_cachedAreaCount' : '0';

  String _refreshLockText() => _areaRefreshLockedToday ? '오늘 완료' : '가능';

  List<String> _filterBranchAreas({
    required List<String> areaNames,
    required String division,
  }) {
    final normalizedDivision = division.trim();

    return areaNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => e != normalizedDivision)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>?> _readCachedAreas(String division) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_areasCacheKey(division));
  }

  Future<void> _writeCachedAreas(String division, List<String> areas) async {
    final prefs = await SharedPreferences.getInstance();
    final filtered = _filterBranchAreas(
      areaNames: areas,
      division: division,
    );
    await prefs.setStringList(_areasCacheKey(division), filtered);
  }

  Future<List<String>> _fetchAreasFromRepository(String division) async {
    final areaRepository = context.read<AreaRepository>();
    final rawNames = await areaRepository.getAreaNamesByDivision(division);

    return _filterBranchAreas(
      areaNames: rawNames,
      division: division,
    );
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

  Future<_BranchWorkStatusAreaCount> _buildAreaCount(String area) async {
    final results = await Future.wait<int>([
      _countPlates(area: area, plateType: PlateType.parkingCompleted),
      _countPlates(area: area, plateType: PlateType.departureCompleted),
    ]);

    return _BranchWorkStatusAreaCount(
      areaName: area,
      parkingCompletedCount: results[0],
      departureCompletedCount: results[1],
    );
  }

  Future<_BranchWorkStatusViewData> _load({
    required bool forceRefreshAreas,
  }) async {
    final division = widget.division.trim();

    if (division.isEmpty) {
      return const _BranchWorkStatusViewData(
        division: '',
        areaNames: [],
        areaCounts: [],
        usedCachedAreas: false,
      );
    }

    List<String> areaNames = [];

    if (!forceRefreshAreas) {
      final cached = await _readCachedAreas(division);
      if (cached != null) {
        areaNames = _filterBranchAreas(
          areaNames: cached,
          division: division,
        );
      }
    }

    bool usedCachedAreas = areaNames.isNotEmpty;

    if (areaNames.isEmpty) {
      areaNames = await _fetchAreasFromRepository(division);
      await _writeCachedAreas(division, areaNames);
      usedCachedAreas = false;
    }

    final areaCounts = await Future.wait<_BranchWorkStatusAreaCount>(
      areaNames.map(_buildAreaCount),
    );

    return _BranchWorkStatusViewData(
      division: division,
      areaNames: areaNames,
      areaCounts: areaCounts,
      usedCachedAreas: usedCachedAreas,
    );
  }

  void _loadInitial() {
    if (_hasRequestedLoad || _future != null) return;
    setState(() {
      _hasRequestedLoad = true;
      _future = _load(forceRefreshAreas: false);
    });
  }

  Future<void> _refreshAreas() async {
    if (_isRefreshingAreas || _isRefreshingAggregations) return;
    if (_areaRefreshLockedToday) return;

    final nextFuture = _load(forceRefreshAreas: true);
    final division = widget.division.trim();
    final today = _todayStamp;

    setState(() {
      _hasRequestedLoad = true;
      _isRefreshingAreas = true;
      _future = nextFuture;
    });

    try {
      final data = await nextFuture;
      await _writeLastAreaRefreshDay(division, today);
      _syncMetaFromAreas(
        division: division,
        areaNames: data.areaNames,
        refreshedDay: today,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isRefreshingAreas = false;
      });
    }
  }

  Future<void> _refreshAggregations() async {
    if (_isRefreshingAreas || _isRefreshingAggregations) return;

    final division = widget.division.trim();
    final cached = await _readCachedAreas(division);

    if ((cached ?? []).isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasRequestedLoad = true;
        _future = _load(forceRefreshAreas: false);
      });
      return;
    }

    final nextFuture = _load(forceRefreshAreas: false);

    setState(() {
      _hasRequestedLoad = true;
      _isRefreshingAggregations = true;
      _future = nextFuture;
    });

    try {
      final data = await nextFuture;
      _syncMetaFromAreas(
        division: division,
        areaNames: data.areaNames,
      );
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

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.domain_rounded, color: cs.onPrimary),
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
                  style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onInverseSurface,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '업무 메뉴 영역에서 지사별 주차·출차 집계를 확인합니다.',
                  maxLines: 2,
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
            label: _cacheCountText(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.sync_rounded,
        label: '로딩',
        loading: true,
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.error_outline_rounded,
        label: '오류',
      ),
    );
  }

  Widget _buildEmptyDivisionState(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: _BranchStateCard(
        icon: Icons.badge_outlined,
        label: 'division 없음',
      ),
    );
  }

  Widget _buildLoadedState(
    BuildContext context,
    _BranchWorkStatusViewData data,
  ) {
    final parkingTotal = data.areaCounts.fold<int>(
      0,
      (sum, item) => sum + item.parkingCompletedCount,
    );
    final departureTotal = data.areaCounts.fold<int>(
      0,
      (sum, item) => sum + item.departureCompletedCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BranchMetricStrip(
          division: data.division,
          branchCount: data.areaCounts.length,
          cachedCount: _cachedAreaCount,
          parkingTotal: parkingTotal,
          departureTotal: departureTotal,
          refreshLockText: _refreshLockText(),
          lockedToday: _areaRefreshLockedToday,
        ),
        const SizedBox(height: 12),
        data.areaCounts.isEmpty
            ? const _BranchStateCard(
                icon: Icons.location_off_rounded,
                label: '지사 없음',
              )
            : _BranchSectionFrame(
                title: '지사',
                child: AreaChatInboxScope(
                  areaNames: data.areaCounts
                      .map((item) => item.areaName)
                      .toList(growable: false),
                  builder: (context, inbox, currentUserId) {
                    return Column(
                      children: data.areaCounts
                          .map(
                            (item) => _BranchAreaMiniCard(
                              item: item,
                              unreadCount: inbox.unreadCountForArea(
                                item.areaName,
                                currentUserId,
                              ),
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
      return _BranchGuideCard(
        division: widget.division.trim(),
        cachedAreaCountText: _cacheCountText(),
        refreshLockText: _refreshLockText(),
        lockedToday: _areaRefreshLockedToday,
      );
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
              areaNames: [],
              areaCounts: [],
              usedCachedAreas: false,
            );

        if (data.division.isEmpty) {
          return _buildEmptyDivisionState(context);
        }

        return _buildLoadedState(context, data);
      },
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BranchDialogActionButton(
            icon: Icons.sync_rounded,
            label: '집계 갱신',
            loading: _isRefreshingAggregations,
            disabled: false,
            onPressed: _refreshAggregations,
            primary: false,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _BranchDialogActionButton(
            icon: Icons.refresh_rounded,
            label: _areaRefreshLockedToday ? '지역 완료' : '지역 갱신',
            loading: _isRefreshingAreas,
            disabled: _areaRefreshLockedToday,
            onPressed: _refreshAreas,
            primary: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(context),
        const SizedBox(height: 12),
        _buildBody(context),
        const SizedBox(height: 12),
        _buildActions(context),
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

class _BranchMetricStrip extends StatelessWidget {
  const _BranchMetricStrip({
    required this.division,
    required this.branchCount,
    required this.cachedCount,
    required this.parkingTotal,
    required this.departureTotal,
    required this.refreshLockText,
    required this.lockedToday,
  });

  final String division;
  final int branchCount;
  final int cachedCount;
  final int parkingTotal;
  final int departureTotal;
  final String refreshLockText;
  final bool lockedToday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _BranchMetricChip(
            icon: Icons.corporate_fare_rounded,
            label: '본부',
            value: division.isEmpty ? '-' : division,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          _BranchMetricChip(
            icon: Icons.domain_rounded,
            label: '지사',
            value: '$branchCount',
            color: cs.secondary,
          ),
          const SizedBox(width: 8),
          _BranchMetricChip(
            icon: Icons.local_parking_rounded,
            label: '주차',
            value: '$parkingTotal',
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          _BranchMetricChip(
            icon: Icons.exit_to_app_rounded,
            label: '출차',
            value: '$departureTotal',
            color: cs.tertiary,
          ),
          const SizedBox(width: 8),
          _BranchMetricChip(
            icon: Icons.sd_storage_rounded,
            label: '캐시',
            value: '$cachedCount',
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          _BranchMetricChip(
            icon: lockedToday ? Icons.lock_clock_rounded : Icons.refresh_rounded,
            label: '지역',
            value: refreshLockText,
            color: lockedToday ? cs.error : cs.secondary,
          ),
        ],
      ),
    );
  }
}

class _BranchMetricChip extends StatelessWidget {
  const _BranchMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withOpacity(.10), cs.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchGuideCard extends StatelessWidget {
  const _BranchGuideCard({
    required this.division,
    required this.cachedAreaCountText,
    required this.refreshLockText,
    required this.lockedToday,
  });

  final String division;
  final String cachedAreaCountText;
  final String refreshLockText;
  final bool lockedToday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.domain_verification_rounded, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '대기',
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
          const SizedBox(height: 12),
          _BranchMetricStrip(
            division: division,
            branchCount: int.tryParse(cachedAreaCountText) ?? 0,
            cachedCount: int.tryParse(cachedAreaCountText) ?? 0,
            parkingTotal: 0,
            departureTotal: 0,
            refreshLockText: refreshLockText,
            lockedToday: lockedToday,
          ),
        ],
      ),
    );
  }
}

class _BranchStateCard extends StatelessWidget {
  const _BranchStateCard({
    required this.icon,
    required this.label,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
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
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchDialogActionButton extends StatelessWidget {
  const _BranchDialogActionButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.disabled,
    required this.onPressed,
    required this.primary,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final bool disabled;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = !disabled && !loading;
    final baseColor = primary ? cs.primary : cs.secondary;
    final effectiveColor = enabled ? baseColor : cs.onSurfaceVariant.withOpacity(.48);

    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: primary ? cs.onPrimary : cs.onSecondaryContainer,
                ),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: primary ? effectiveColor : Color.alphaBlend(effectiveColor.withOpacity(.12), cs.surface),
          foregroundColor: primary ? cs.onPrimary : effectiveColor,
          disabledBackgroundColor: cs.surfaceVariant.withOpacity(.34),
          disabledForegroundColor: cs.onSurfaceVariant.withOpacity(.48),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: effectiveColor.withOpacity(primary ? .0 : .28)),
        ),
      ),
    );
  }
}

class _BranchWorkStatusViewData {
  const _BranchWorkStatusViewData({
    required this.division,
    required this.areaNames,
    required this.areaCounts,
    required this.usedCachedAreas,
  });

  final String division;
  final List<String> areaNames;
  final List<_BranchWorkStatusAreaCount> areaCounts;
  final bool usedCachedAreas;
}

class _BranchWorkStatusAreaCount {
  const _BranchWorkStatusAreaCount({
    required this.areaName,
    required this.parkingCompletedCount,
    required this.departureCompletedCount,
  });

  final String areaName;
  final int parkingCompletedCount;
  final int departureCompletedCount;
}


class _AreaChatReadOpenHelper {
  const _AreaChatReadOpenHelper._();

  static Future<void> open({
    required BuildContext context,
    required String areaName,
  }) async {
    final area = areaName.trim();
    if (area.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: AreaChatPanel(
            areaName: area,
            showCloseButton: true,
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        );
      },
    );
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
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 92,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                        unreadCount: unreadCount,
                        onPressed: () => _openChat(context),
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
                ],
              ),
            ),
          ),
        ],
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
