import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/auth/google_auth_session.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/calendar/calendar_public_text.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../headquarter/widgets/calendar/google_calendar_service.dart';
import '../../selector/application/dev_auth.dart';
import '../../sprint/application/sprint_mode_store.dart';
import '../../sprint/domain/sprint_models.dart';
import '../../sprint/pages/sprint_ui.dart';
import 'headquarter_calendar_side_dock.dart';

Future<void> showHeadquarterCalendarAccountSideDock({
  required BuildContext context,
  required SprintModeStore store,
}) async {
  HeadquarterCalendarSideDockDiagnostics.log(
    'account_dock_open presentation=operations_left_side_dock layout=ops_list_surface profiles=${store.calendarProfiles.length} state=${store.calendarState.name}',
  );
  await showOperationsLeftSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '캘린더 연결',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: true,
    builder: (dockContext) => _HeadquarterCalendarAccountSideDock(store: store),
  );
  HeadquarterCalendarSideDockDiagnostics.log(
    'account_dock_closed presentation=operations_left_side_dock profiles=${store.calendarProfiles.length} state=${store.calendarState.name}',
  );
}

class _HeadquarterCalendarAccountSideDock extends StatefulWidget {
  const _HeadquarterCalendarAccountSideDock({required this.store});

  final SprintModeStore store;

  @override
  State<_HeadquarterCalendarAccountSideDock> createState() =>
      _HeadquarterCalendarAccountSideDockState();
}

class _HeadquarterCalendarAccountSideDockState
    extends State<_HeadquarterCalendarAccountSideDock> {
  String? _busyProfileId;
  String? _expandedProfileId;
  bool _discoveringCalendars = false;
  List<GoogleCalendarAccessEntry>? _calendarCandidates;

  bool get _busy =>
      _discoveringCalendars ||
      _busyProfileId != null ||
      widget.store.accountBusy;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    super.dispose();
  }

  void _handleStoreChanged() {
    if (mounted) setState(() {});
  }

  String _errorMessage(Object error) {
    if (error is GoogleAccountMismatchException) {
      return '현재 연결 계정으로 이 캘린더를 사용할 수 없습니다.';
    }
    if (error is StateError) {
      if (error.message == 'interactive_google_auth_not_supported') {
        return '이 환경에서는 캘린더 연결을 진행할 수 없습니다.';
      }
      if (error.message == 'calendar_profile_account_mismatch') {
        return '현재 연결 계정으로 이 캘린더를 사용할 수 없습니다.';
      }
      if (error.message == 'calendar_profile_account_missing') {
        return '저장된 캘린더 연결 정보를 사용할 수 없습니다.';
      }
      if (error.message == 'calendar_profile_not_found') {
        return '저장된 캘린더 정보를 찾지 못했습니다.';
      }
      if (error.message == 'calendar_profile_duplicate') {
        return '같은 캘린더가 이미 연결되어 있습니다.';
      }
      if (error.message == 'company_calendar_slot_occupied') {
        return '회사 캘린더는 1개만 연결할 수 있습니다.';
      }
      if (error.message == 'personal_calendar_slot_fixed') {
        return '내 캘린더는 현재 연결 계정의 기본 캘린더로 유지됩니다.';
      }
      if (error.message == 'google_primary_calendar_not_found') {
        return '현재 연결 계정의 기본 캘린더를 찾지 못했습니다.';
      }
      if (error.message == 'calendar_write_access_required') {
        return '이 캘린더에서는 일정을 변경할 수 없습니다.';
      }
      if (error.message == 'account_operation_in_progress') {
        return '캘린더 연결 작업이 진행 중입니다.';
      }
    }
    final message = error.toString().toLowerCase();
    if (message.contains('status: 403') || message.contains('status 403')) {
      return '이 캘린더에 접근할 수 없습니다.';
    }
    if (message.contains('status: 404') || message.contains('status 404')) {
      return '캘린더를 찾지 못했거나 접근할 수 없습니다.';
    }
    return '캘린더 작업을 완료하지 못했습니다.';
  }

  String _connectionLabel(SprintCalendarConnectionState state) {
    switch (state) {
      case SprintCalendarConnectionState.notConnected:
        return '연결 안 됨';
      case SprintCalendarConnectionState.cached:
        return '연결 준비';
      case SprintCalendarConnectionState.reauthenticationRequired:
        return '재인증 필요';
      case SprintCalendarConnectionState.switching:
        return '확인 중';
      case SprintCalendarConnectionState.syncing:
        return '동기화 중';
      case SprintCalendarConnectionState.connected:
        return '연결됨';
      case SprintCalendarConnectionState.failed:
        return '동기화 실패';
    }
  }

  IconData _connectionIcon(SprintCalendarConnectionState state) {
    switch (state) {
      case SprintCalendarConnectionState.notConnected:
        return Icons.link_off_rounded;
      case SprintCalendarConnectionState.cached:
        return Icons.link_rounded;
      case SprintCalendarConnectionState.reauthenticationRequired:
        return Icons.lock_person_outlined;
      case SprintCalendarConnectionState.switching:
      case SprintCalendarConnectionState.syncing:
        return Icons.sync_rounded;
      case SprintCalendarConnectionState.connected:
        return Icons.event_available_outlined;
      case SprintCalendarConnectionState.failed:
        return Icons.error_outline_rounded;
    }
  }

  Future<void> _showDeveloperStatus() async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '캘린더 연결 Side Dock 상태',
      initialMessage: '본사 캘린더 연결 Side Dock 상태를 확인합니다.',
      useCommonUi: true,
      showDialogImmediately: false,
      developerModeMessage:
          '개발자 모드 ON: Side Dock 상태의 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: Side Dock 상태 로그만 콘솔에 기록합니다.',
    );
    if (!mounted) return;
    trace.log(
      'presentation=operations_left_side_dock layout=ops_list_surface '
      'profiles=${widget.store.calendarProfiles.length} '
      'personal=${widget.store.personalCalendarProfile?.id ?? ''} '
      'company=${widget.store.companyCalendarProfile?.id ?? ''} '
      'default=${widget.store.defaultCalendarProfileId ?? ''} '
      'state=${widget.store.calendarState.name} '
      'busy=$_busy discovering=$_discoveringCalendars '
      'expanded=${_expandedProfileId ?? ''} '
      'candidates=${_calendarCandidates?.length ?? 0}',
      progress: 1,
    );
    await trace.succeed('캘린더 연결 Side Dock 상태 확인을 완료했습니다.');
    if (!mounted || !trace.developerMode) return;
    await trace.showSnapshotStatusDialog(
      context,
      title: '캘린더 연결 Side Dock 상태',
      description:
          'List Surface 연결 상태와 동작의 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  Future<void> _syncAll() async {
    if (_busy || widget.store.calendarProfiles.isEmpty) return;
    setState(() => _busyProfileId = 'all');
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '전체 캘린더 동기화',
      initialMessage: '연결된 일정을 모두 내려받고 있습니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 전체 동기화 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 전체 동기화 로그를 콘솔에 기록합니다.',
    );
    try {
      final reports = await widget.store.syncGoogleCalendar();
      for (final report in reports) {
        trace.log(
          'profile=${report.profileId} calendar=${report.calendarId} '
          'mode=${report.mode.name} pages=${report.pageCount} '
          'received=${report.receivedCount} inserted=${report.insertedCount} '
          'updated=${report.updatedCount} deleted=${report.deletedCount} '
          'success=${report.success} error=${report.error ?? ''}',
          progress: .75,
        );
      }
      final success = widget.store.calendarState ==
          SprintCalendarConnectionState.connected;
      if (success) {
        await trace.succeed('연결된 캘린더 동기화를 완료했습니다.');
      } else {
        await trace.fail('일부 캘린더의 동기화를 완료하지 못했습니다.');
      }
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: success
            ? '연결된 캘린더를 모두 동기화했습니다.'
            : '일부 캘린더의 연결 상태를 확인하세요.',
        danger: !success,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _syncProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    setState(() => _busyProfileId = profile.id);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '캘린더 동기화',
      initialMessage: '${calendarPublicLabel(profile.label)} 캘린더를 동기화합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 캘린더 동기화 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 캘린더 동기화 로그를 콘솔에 기록합니다.',
    );
    try {
      final report = await widget.store.syncCalendarProfile(profile.id);
      trace.log(
        'profile=${profile.id} mode=${report.mode.name} '
        'received=${report.receivedCount} inserted=${report.insertedCount} '
        'updated=${report.updatedCount} deleted=${report.deletedCount}',
        progress: .8,
      );
      final state = widget.store.calendarStateForProfile(profile.id);
      if (state == SprintCalendarConnectionState.connected) {
        await trace.succeed('${calendarPublicLabel(profile.label)} 캘린더 동기화를 완료했습니다.');
      } else {
        await trace.fail('${calendarPublicLabel(profile.label)} 캘린더 동기화를 완료하지 못했습니다.');
      }
    } catch (error, stackTrace) {
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _authenticateProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    setState(() => _busyProfileId = profile.id);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '캘린더 재인증',
      initialMessage: '${calendarPublicLabel(profile.label)} 캘린더 권한을 갱신합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 재인증 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 재인증 로그를 콘솔에 기록합니다.',
    );
    try {
      await widget.store.authenticateCalendarProfile(profile.id);
      await widget.store.syncCalendarProfile(profile.id, interactive: false);
      await trace.succeed('${calendarPublicLabel(profile.label)} 캘린더 권한을 갱신했습니다.');
    } catch (error, stackTrace) {
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _setDefault(SprintCalendarProfile profile) async {
    if (_busy || profile.id == widget.store.defaultCalendarProfileId) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.setDefaultCalendarProfile(profile.id);
      HeadquarterCalendarSideDockDiagnostics.log(
        'account_default_changed profile=${profile.id} calendar=${profile.calendarId}',
      );
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: '${calendarPublicLabel(profile.label)} 캘린더를 기본 캘린더로 설정했습니다.',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _renameProfile(SprintCalendarProfile profile) async {
    if (_busy) return;
    final controller = TextEditingController(text: calendarPublicLabel(profile.label));
    final next = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('캘린더 이름'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || next.isEmpty || !mounted) return;
    setState(() => _busyProfileId = profile.id);
    try {
      await widget.store.updateCalendarProfile(
        profileId: profile.id,
        label: next,
        locked: profile.locked,
      );
      HeadquarterCalendarSideDockDiagnostics.log(
        'account_profile_renamed profile=${profile.id} label=$next',
      );
    } catch (error) {
      if (!mounted) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _removeProfile(SprintCalendarProfile profile) async {
    if (_busy || profile.googlePrimary) return;
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('회사 캘린더 연결 해제'),
            content: Text(
              '${calendarPublicLabel(profile.label)} 연결을 해제할까요? 원본 일정은 삭제되지 않습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('연결 해제'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busyProfileId = profile.id);
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '회사 캘린더 연결 해제',
      initialMessage: '회사 캘린더 연결을 해제합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 연결 해제 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 연결 해제 로그를 콘솔에 기록합니다.',
    );
    try {
      await widget.store.removeCalendarProfile(profile.id);
      await trace.succeed('회사 캘린더 연결을 해제했습니다.');
      if (mounted) {
        setState(() {
          _expandedProfileId = null;
          _calendarCandidates = null;
        });
      }
    } catch (error, stackTrace) {
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Future<void> _discoverCompanyCalendars() async {
    if (_busy || widget.store.hasCompanyCalendarProfile) return;
    setState(() {
      _discoveringCalendars = true;
      _calendarCandidates = null;
    });
    HeadquarterCalendarSideDockDiagnostics.log(
      'account_company_discovery_start presentation=inline_list_surface',
    );
    try {
      final calendars = await widget.store.discoverAccessibleGoogleCalendars();
      if (!mounted) return;
      final connectedIds = widget.store.calendarProfiles
          .map((profile) => profile.calendarId.trim().toLowerCase())
          .toSet();
      final candidates = calendars
          .where((entry) => !entry.primary)
          .where((entry) => entry.canEditEvents)
          .where((entry) => !connectedIds.contains(entry.id.trim().toLowerCase()))
          .toList(growable: false);
      setState(() => _calendarCandidates = candidates);
      HeadquarterCalendarSideDockDiagnostics.log(
        'account_company_discovery_complete candidates=${candidates.length}',
      );
    } catch (error, stackTrace) {
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '공유 캘린더 검색',
        initialMessage: '회사 캘린더 후보를 불러오지 못했습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 공유 캘린더 검색 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage:
            '개발자 모드 OFF: 공유 캘린더 검색 로그를 콘솔에 기록합니다.',
      );
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _discoveringCalendars = false);
    }
  }

  Future<void> _connectCandidate(GoogleCalendarAccessEntry selected) async {
    if (_busy) return;
    setState(() => _busyProfileId = 'candidate:${selected.id}');
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '회사 캘린더 연결',
      initialMessage: '${selected.displayName} 캘린더를 연결합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 회사 캘린더 연결 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 회사 캘린더 연결 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'calendar=${selected.id} name=${selected.displayName} '
      'accessRole=${selected.accessRole} primary=${selected.primary}',
      progress: .2,
    );
    try {
      final profile = await widget.store.addGoogleCalendarProfile(
        label: calendarPublicLabel(selected.displayName),
        calendarId: selected.id,
        locked: true,
        makeActive: false,
      );
      trace.log(
        'profile=${profile.id} canEdit=${profile.canEditEvents} '
        'canManageSharing=${profile.canManageSharing}',
        progress: .88,
      );
      await trace.succeed('회사 캘린더를 연결했습니다.');
      if (!mounted) return;
      setState(() => _calendarCandidates = null);
      if (!trace.developerMode) {
        sprintShowMessage(
          context: context,
          message: '회사 캘린더를 연결했습니다.',
        );
      }
    } catch (error, stackTrace) {
      await trace.fail(
        _errorMessage(error),
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || trace.developerMode) return;
      sprintShowMessage(
        context: context,
        message: _errorMessage(error),
        danger: true,
      );
    } finally {
      if (mounted) setState(() => _busyProfileId = null);
    }
  }

  Widget _divider(CommonUiTokens tokens) {
    return Divider(height: 1, thickness: 1, color: tokens.borderSubtle);
  }

  Widget _listRow({
    required CommonUiTokens tokens,
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
    bool selected = false,
    bool enabled = true,
    Widget? trailingWidget,
  }) {
    final content = Row(
      children: [
        Icon(icon, color: enabled ? tokens.accent : tokens.textSecondary, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? tokens.textPrimary : tokens.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (trailingWidget != null)
          trailingWidget
        else ...[
          AnimatedSwitcher(
            duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: .96, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              trailing,
              key: ValueKey<String>(trailing),
              style: TextStyle(
                color: tokens.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: tokens.textSecondary, size: 18),
        ],
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : .55,
      child: IgnorePointer(
        ignoring: !enabled,
        child: OpsDockSelectableRowSurface(
          selected: selected,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }

  Widget _profileActions(
    CommonUiTokens tokens,
    SprintCalendarProfile profile,
  ) {
    final active = profile.id == widget.store.defaultCalendarProfileId;
    final state = widget.store.calendarStateForProfile(profile.id);
    final actions = <Widget>[];
    void addAction(
      IconData icon,
      String label,
      VoidCallback callback, {
      bool enabled = true,
    }) {
      if (actions.isNotEmpty) actions.add(_divider(tokens));
      actions.add(
        _listRow(
          tokens: tokens,
          icon: icon,
          title: label,
          subtitle: '',
          trailing: '',
          trailingWidget: Icon(
            Icons.chevron_right_rounded,
            color: tokens.textSecondary,
            size: 18,
          ),
          onTap: callback,
          enabled: enabled,
        ),
      );
    }

    if (!active) {
      addAction(
        Icons.star_outline_rounded,
        '기본 캘린더로 설정',
        () => _setDefault(profile),
        enabled: !_busy,
      );
    }
    addAction(
      Icons.sync_rounded,
      '지금 동기화',
      () => _syncProfile(profile),
      enabled: !_busy,
    );
    if (state == SprintCalendarConnectionState.reauthenticationRequired ||
        state == SprintCalendarConnectionState.failed) {
      addAction(
        Icons.lock_person_outlined,
        '연결 권한 갱신',
        () => _authenticateProfile(profile),
        enabled: !_busy,
      );
    }
    addAction(
      Icons.edit_outlined,
      '이름 변경',
      () => _renameProfile(profile),
      enabled: !_busy,
    );
    if (!profile.googlePrimary) {
      addAction(
        Icons.link_off_rounded,
        '연결 해제',
        () => _removeProfile(profile),
        enabled: !_busy,
      );
    }
    return AnimatedSize(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(children: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final state = widget.store.calendarState;
    final profiles = widget.store.calendarProfiles;
    final active = widget.store.defaultCalendarProfile;
    final company = widget.store.companyCalendarProfile;
    final candidates = _calendarCandidates;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 190);

    final rows = <Widget>[];
    void addRow(Widget row) {
      if (rows.isNotEmpty) rows.add(_divider(tokens));
      rows.add(row);
    }

    addRow(
      _listRow(
        tokens: tokens,
        icon: _connectionIcon(state),
        title: '연결 상태',
        subtitle: profiles.isEmpty ? '연결된 캘린더 없음' : '',
        trailing: _connectionLabel(state),
        onTap: _busy || profiles.isEmpty ? () {} : _syncAll,
        enabled: !_busy && profiles.isNotEmpty,
      ),
    );

    addRow(
      _listRow(
        tokens: tokens,
        icon: Icons.star_rounded,
        title: '기본 캘린더',
        subtitle: '',
        trailing: active == null ? '없음' : calendarPublicLabel(active.label),
        onTap: () {
          if (active == null) return;
          setState(() {
            _expandedProfileId =
                _expandedProfileId == active.id ? null : active.id;
          });
        },
        enabled: active != null,
      ),
    );

    for (final profile in profiles) {
      final profileState = widget.store.calendarStateForProfile(profile.id);
      final expanded = _expandedProfileId == profile.id;
      addRow(
        Column(
          children: [
            _listRow(
              tokens: tokens,
              icon: profile.googlePrimary
                  ? Icons.person_outline_rounded
                  : Icons.business_outlined,
              title: calendarPublicLabel(profile.label),
              subtitle:
                  '${profile.slotLabel} · ${profile.canEditEvents ? '편집 가능' : '읽기 전용'}',
              trailing: _connectionLabel(profileState),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _expandedProfileId = expanded ? null : profile.id;
                  _calendarCandidates = null;
                });
                HeadquarterCalendarSideDockDiagnostics.log(
                  'account_profile_toggle profile=${profile.id} expanded=${!expanded}',
                );
              },
              selected: expanded,
              enabled: !_busy,
            ),
            AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -.025),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: expanded
                  ? KeyedSubtree(
                      key: ValueKey<String>('actions-${profile.id}'),
                      child: _profileActions(tokens, profile),
                    )
                  : SizedBox(
                      key: ValueKey<String>('actions-empty-${profile.id}'),
                    ),
            ),
          ],
        ),
      );
    }

    addRow(
      _listRow(
        tokens: tokens,
        icon: Icons.sync_rounded,
        title: '모든 캘린더 동기화',
        subtitle: '',
        trailing: '',
        trailingWidget: _busyProfileId == 'all'
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.1),
              )
            : Icon(
                Icons.chevron_right_rounded,
                color: tokens.textSecondary,
                size: 18,
              ),
        onTap: _syncAll,
        enabled: !_busy && profiles.isNotEmpty,
      ),
    );

    addRow(
      _listRow(
        tokens: tokens,
        icon: Icons.add_business_rounded,
        title: company == null ? '회사 캘린더 연결' : '회사 캘린더',
        subtitle: '',
        trailing: company == null ? '추가' : calendarPublicLabel(company.label),
        trailingWidget: _discoveringCalendars
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.1),
              )
            : null,
        onTap: _discoverCompanyCalendars,
        enabled: !_busy && company == null,
      ),
    );

    final candidateSurface = candidates == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: CommonSideDockReveal(
              order: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '회사 캘린더 선택',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  OpsDockListSurface(
                    child: candidates.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '연결할 수 있는 공유 캘린더가 없습니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (var index = 0;
                                  index < candidates.length;
                                  index++) ...[
                                if (index > 0) _divider(tokens),
                                _listRow(
                                  tokens: tokens,
                                  icon: Icons.event_note_outlined,
                                  title: calendarPublicLabel(
                                    candidates[index].displayName,
                                  ),
                                  subtitle: candidates[index].accessLabel,
                                  trailing: '연결',
                                  onTap: () => _connectCandidate(
                                    candidates[index],
                                  ),
                                  enabled: !_busy,
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: CommonSideDockFrame(
        title: '캘린더 연결',
        subtitle: '',
        icon: Icons.calendar_month_rounded,
        onClose: () => Navigator.of(context).pop(),
        onLongPress: _showDeveloperStatus,
        headerAction: ValueListenableBuilder<bool>(
          valueListenable: DevAuth.devModeEnabled,
          builder: (context, enabled, child) {
            if (!enabled) return const SizedBox.shrink();
            return IconButton(
              onPressed: _showDeveloperStatus,
              tooltip: '상태',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.bug_report_outlined,
                color: tokens.textSecondary,
                size: 19,
              ),
            );
          },
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(right: 2, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommonSideDockReveal(
                order: 1,
                child: OpsDockListSurface(
                  child: Column(children: rows),
                ),
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(-.025, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      candidates == null
                          ? 'company-candidates-hidden'
                          : 'company-candidates-${candidates.length}',
                    ),
                    child: candidateSurface,
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
