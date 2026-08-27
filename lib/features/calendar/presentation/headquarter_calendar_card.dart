import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/calendar/calendar_public_text.dart';
import '../../../shared/google_calendar/google_event_colors.dart';
import '../../selector/application/dev_auth.dart';
import '../../sprint/application/sprint_mode_store.dart';
import '../../sprint/domain/sprint_models.dart';
import '../../sprint/pages/sprint_external_event_editor_sheet.dart';
import '../../sprint/pages/sprint_project_workspace_sheet.dart';
import '../../sprint/pages/sprint_task_detail_sheet.dart';
import 'headquarter_calendar_side_dock.dart';

class HeadquarterCalendarCard extends StatefulWidget {
  const HeadquarterCalendarCard({
    super.key,
    this.useCommonUi = false,
    this.showAccountEntry = false,
    this.headerTrailing,
    this.fillViewport = false,
  });

  final bool useCommonUi;
  final bool showAccountEntry;
  final Widget? headerTrailing;
  final bool fillViewport;

  @override
  State<HeadquarterCalendarCard> createState() =>
      _HeadquarterCalendarCardState();
}

class _HeadquarterCalendarCardState extends State<HeadquarterCalendarCard>
    with SingleTickerProviderStateMixin {
  static const List<String> _weekdays = <String>[
    '일',
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
  ];

  late final SprintModeStore _store;
  late final AnimationController _refreshController;
  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  Object? _initializationError;
  StackTrace? _initializationStack;
  bool _refreshing = false;
  bool _disposed = false;
  String _lastLayoutLog = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _store = SprintModeStore()..addListener(_handleStoreChanged);
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    unawaited(DevAuth.isDevModeEnabled());
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshController.dispose();
    _store.removeListener(_handleStoreChanged);
    unawaited(_store.flush());
    _store.dispose();
    super.dispose();
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _initialize() async {
    try {
      await _store.initialize();
      if (_disposed) return;
      _store.ensureCalendarRangeFor(_monthAnchor, immediate: true);
      if (mounted) {
        setState(() {
          _initializationError = null;
          _initializationStack = null;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('[HeadquarterCalendar] initialize failure error=$error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _initializationError = error;
        _initializationStack = stackTrace;
      });
    }
  }

  DateTime get _monthAnchor =>
      DateTime(_visibleMonth.year, _visibleMonth.month, 15);

  List<_HeadquarterCalendarItem> get _items {
    if (!_store.initialized) return const <_HeadquarterCalendarItem>[];
    final visibleProfiles = _store.visibleCalendarProfileIds;
    final items = <_HeadquarterCalendarItem>[];
    for (final task in _store.tasks) {
      if (!task.hasGoogleEvent || task.deleteAfterSync) continue;
      final profileId = task.googleCalendarProfileId;
      if (profileId == null || !visibleProfiles.contains(profileId)) continue;
      if (task.state == SprintTaskState.cancelled) continue;
      final project = _store.projectById(task.projectId);
      items.add(
        _HeadquarterCalendarItem.task(
          task: task,
          profileLabel: calendarPublicLabel(_store.calendarProfileLabel(profileId)),
          projectName: project?.name ?? '스프린트 업무',
          projectIcon: project?.icon ?? Icons.task_alt_rounded,
          projectColorId: project?.googleColorId,
        ),
      );
    }
    for (final event in _store.externalEvents) {
      items.add(
        _HeadquarterCalendarItem.external(
          event: event,
          profileLabel: calendarPublicLabel(_store.calendarProfileLabel(event.calendarProfileId)),
          editable: _store.canEditExternalEvent(event),
        ),
      );
    }
    items.sort(_compareItems);
    return items;
  }

  int _compareItems(
    _HeadquarterCalendarItem left,
    _HeadquarterCalendarItem right,
  ) {
    final start = left.start.compareTo(right.start);
    if (start != 0) return start;
    if (left.isTask != right.isTask) return left.isTask ? -1 : 1;
    return left.title.compareTo(right.title);
  }

  List<_HeadquarterCalendarItem> get _selectedItems => _items
      .where((item) => item.spans(_selectedDay))
      .toList(growable: false)
    ..sort(_compareItems);

  Map<String, _DaySummary> get _monthSummary {
    final result = <String, _DaySummary>{};
    for (final item in _items) {
      var day = _day(item.start);
      final last = item.lastDay;
      while (!day.isAfter(last)) {
        final key = _dateKey(day);
        final current = result[key] ?? const _DaySummary();
        result[key] = _DaySummary(
          count: current.count + 1,
          important: current.important || item.important,
        );
        day = day.add(const Duration(days: 1));
      }
    }
    return result;
  }

  void _moveMonth(int delta) {
    final next = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + delta,
      1,
    );
    final lastDay = DateTime(next.year, next.month + 1, 0).day;
    final selectedDay = _selectedDay.day > lastDay
        ? lastDay
        : _selectedDay.day;
    setState(() {
      _visibleMonth = next;
      _selectedDay = DateTime(next.year, next.month, selectedDay);
    });
    HapticFeedback.selectionClick();
    HeadquarterCalendarSideDockDiagnostics.log(
      'month_move delta=$delta month=${next.toIso8601String()} selected=${_selectedDay.toIso8601String()}',
    );
    _store.ensureCalendarRangeFor(_monthAnchor, immediate: true);
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = _day(day);
      if (day.year != _visibleMonth.year || day.month != _visibleMonth.month) {
        _visibleMonth = DateTime(day.year, day.month, 1);
      }
    });
    HapticFeedback.selectionClick();
    HeadquarterCalendarSideDockDiagnostics.log(
      'day_select date=${_selectedDay.toIso8601String()} count=${_selectedItems.length}',
    );
    _store.ensureCalendarRangeFor(day, immediate: true);
  }

  Future<void> _refresh() async {
    if (_refreshing || !_store.initialized) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() => _refreshing = true);
    HeadquarterCalendarSideDockDiagnostics.log(
      'refresh_start date=${_selectedDay.toIso8601String()}',
    );
    if (!reduceMotion) {
      _refreshController.repeat();
    }
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '본사 일정 갱신',
      initialMessage: '연결된 일정을 갱신하고 있습니다.',
      useCommonUi: widget.useCommonUi,
      developerModeMessage:
          '개발자 모드 ON: 본사 캘린더 동기화 로그를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 본사 캘린더 동기화 로그를 콘솔에 기록합니다.',
    );
    trace.log(
      'profiles=${_store.calendarProfiles.length} '
      'editable=${_store.editableCalendarProfiles.length} '
      'anchor=${_selectedDay.toIso8601String()}',
      progress: 0.18,
    );
    try {
      final reports = await _store.syncGoogleCalendarFor(_selectedDay);
      for (final report in reports) {
        trace.log(
          'profile=${report.profileId} calendar=${report.calendarId} '
          'mode=${report.mode.name} pages=${report.pageCount} '
          'received=${report.receivedCount} inserted=${report.insertedCount} '
          'updated=${report.updatedCount} deleted=${report.deletedCount} '
          'unlinkedTasks=${report.unlinkedTaskCount} '
          'tokenReset=${report.tokenReset} '
          'periodicVerification=${report.periodicVerification} '
          'fullReason=${report.fullSyncReason?.name ?? ''} '
          'success=${report.success} error=${report.error ?? ''}',
          progress: 0.74,
        );
      }
      final failedProfiles = _store.calendarProfiles.where((profile) {
        final state = _store.calendarStateForProfile(profile.id);
        return state == SprintCalendarConnectionState.failed ||
            state == SprintCalendarConnectionState.reauthenticationRequired;
      }).toList(growable: false);
      trace.log(
        'externalEvents=${_store.externalEvents.length} '
        'linkedTasks=${_store.tasks.where((task) => task.hasGoogleEvent).length} '
        'failedProfiles=${failedProfiles.length}',
        progress: 0.9,
      );
      if (failedProfiles.isNotEmpty) {
        for (final profile in failedProfiles) {
          trace.log(
            'profile=${profile.id} calendar=${profile.calendarId} '
            'state=${_store.calendarStateForProfile(profile.id).name} '
            'error=${_store.calendarErrorForProfile(profile.id) ?? ''}',
          );
        }
        if (failedProfiles.length == _store.calendarProfiles.length) {
          await trace.fail('연결된 일정의 갱신에 실패했습니다.');
        } else {
          await trace.succeed('일부 캘린더를 제외하고 일정을 갱신했습니다.');
        }
      } else {
        await trace.succeed('본사 캘린더 일정을 최신 상태로 갱신했습니다.');
      }
    } catch (error, stackTrace) {
      await trace.fail(
        '본사 캘린더 일정 갱신에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _refreshController.stop();
      _refreshController.value = 0;
      if (mounted) setState(() => _refreshing = false);
      HeadquarterCalendarSideDockDiagnostics.log(
        'refresh_end date=${_selectedDay.toIso8601String()} count=${_selectedItems.length}',
      );
    }
  }

  Future<void> _openCreate() async {
    if (!_store.initialized) return;
    HeadquarterCalendarSideDockDiagnostics.log(
      'create_request date=${_selectedDay.toIso8601String()}',
    );
    if (_store.editableCalendarProfiles.isEmpty) {
      await _showInfoDialog(
        title: '일정 추가',
        message: '일정 변경 권한이 있는 캘린더를 먼저 연결하세요.',
      );
      return;
    }
    await showSprintExternalEventEditorSheet(
      context: context,
      store: _store,
      initialDate: _selectedDay,
      initialCalendarProfileId: _store.defaultCalendarProfile?.id,
    );
  }

  Future<void> _openItem(_HeadquarterCalendarItem item) async {
    HeadquarterCalendarSideDockDiagnostics.log(
      'item_request id=${item.id} task=${item.isTask} editable=${item.editable}',
    );
    if (item.isTask) {
      await _showTaskDetail(item);
      return;
    }
    await _showExternalDetail(item);
  }

  Future<void> _showTaskDetail(_HeadquarterCalendarItem item) async {
    await _showDetailDialog(
      item: item,
      actionLabel: '업무 관리',
      actionIcon: Icons.edit_calendar_rounded,
      onAction: () async {
        Navigator.of(context).pop();
        await showSprintTaskDetailSheet(
          context: context,
          store: _store,
          taskId: item.taskId!,
        );
      },
    );
  }

  Future<void> _showExternalDetail(_HeadquarterCalendarItem item) async {
    await _showDetailDialog(
      item: item,
      actionLabel: item.editable ? '일정 관리' : null,
      actionIcon: Icons.edit_calendar_rounded,
      onAction: item.editable
          ? () async {
              Navigator.of(context).pop();
              final event = _store.externalEventById(item.externalEventId);
              if (event == null || !mounted) return;
              await showSprintExternalEventEditorSheet(
                context: context,
                store: _store,
                event: event,
              );
            }
          : null,
    );
  }

  Future<void> _showDetailDialog({
    required _HeadquarterCalendarItem item,
    String? actionLabel,
    IconData actionIcon = Icons.edit_rounded,
    Future<void> Function()? onAction,
  }) async {
    Widget builder(BuildContext dialogContext) {
      final cs = Theme.of(dialogContext).colorScheme;
      final color = _itemColor(dialogContext, item);
      return Dialog(
        elevation: 12,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color.withOpacity(.12),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(item.icon, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(dialogContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        label: _rangeLabel(item),
                      ),
                      _InfoChip(
                        icon: Icons.calendar_month_rounded,
                        label: item.profileLabel,
                      ),
                      _InfoChip(
                        icon: item.isTask
                            ? Icons.bolt_rounded
                            : item.editable
                                ? Icons.edit_rounded
                                : Icons.lock_outline_rounded,
                        label: item.isTask
                            ? item.projectName
                            : item.editable
                                ? '편집 가능'
                                : '읽기 전용',
                      ),
                    ],
                  ),
                  if (item.description.trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        item.description.trim(),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('닫기'),
                      ),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: onAction,
                          icon: Icon(actionIcon),
                          label: Text(actionLabel),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.useCommonUi) {
      await showCommonOverlayDialog<void>(
        context: context,
        builder: builder,
      );
      return;
    }
    await showDialog<void>(context: context, builder: builder);
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) async {
    Widget builder(BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('확인'),
          ),
        ],
      );
    }

    if (widget.useCommonUi) {
      await showCommonOverlayDialog<void>(
        context: context,
        builder: builder,
      );
      return;
    }
    await showDialog<void>(context: context, builder: builder);
  }

  String _calendarStateLabel(SprintCalendarConnectionState state) {
    switch (state) {
      case SprintCalendarConnectionState.notConnected:
        return '연결 안 됨';
      case SprintCalendarConnectionState.cached:
        return '연결 정보 준비됨';
      case SprintCalendarConnectionState.reauthenticationRequired:
        return '재인증 필요';
      case SprintCalendarConnectionState.switching:
        return '계정 전환 중';
      case SprintCalendarConnectionState.syncing:
        return '동기화 중';
      case SprintCalendarConnectionState.connected:
        return '연결됨';
      case SprintCalendarConnectionState.failed:
        return '동기화 실패';
    }
  }

  String get _calendarAccountSubtitle {
    final state = _calendarStateLabel(_store.calendarState);
    final profiles = _store.calendarProfiles;
    final defaultProfile = _store.defaultCalendarProfile;
    if (profiles.isEmpty) return state;
    final defaultLabel = defaultProfile?.label.trim().isNotEmpty == true
        ? calendarPublicLabel(defaultProfile!.label)
        : '기본 캘린더 없음';
    return '$defaultLabel · 총 ${profiles.length}개 · $state';
  }

  String _calendarAccountDiagnostics() {
    final defaultProfile = _store.defaultCalendarProfile;
    return 'initialized=${_store.initialized} '
        'state=${_store.calendarState.name} '
        'profiles=${_store.calendarProfiles.length} '
        'editable=${_store.editableCalendarProfiles.length} '
        'defaultProfile=${defaultProfile?.id ?? ''} '
        'defaultCalendar=${defaultProfile?.calendarId ?? ''} '
        'visible=${_store.visibleCalendarProfileIds.length} '
        'externalEvents=${_store.externalEvents.length} '
        'linkedTasks=${_store.tasks.where((task) => task.hasGoogleEvent).length}';
  }

  Future<void> _showAccountDeveloperStatus() async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '캘린더 연결 상태',
      initialMessage: '본사 Dashboard 캘린더 연결 상태를 확인합니다.',
      useCommonUi: widget.useCommonUi,
      showDialogImmediately: false,
      developerModeMessage:
          '개발자 모드 ON: 현재 계정 상태의 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 계정 상태 로그만 콘솔에 기록합니다.',
    );
    if (!mounted) return;
    trace.log(_calendarAccountDiagnostics(), progress: 1);
    await trace.succeed('캘린더 연결 상태 확인을 완료했습니다.');
    if (!mounted || !trace.developerMode) return;
    await trace.showSnapshotStatusDialog(
      context,
      title: '캘린더 연결 상태',
      description: '현재 계정 상태의 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  Future<void> _openAccountSheet() async {
    if (!_store.initialized ||
        _store.calendarState == SprintCalendarConnectionState.syncing) {
      return;
    }

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '캘린더 연결',
      initialMessage: '캘린더 연결 BottomSheet를 엽니다.',
      useCommonUi: widget.useCommonUi,
      showDialogImmediately: false,
      developerModeMessage:
          '개발자 모드 ON: 계정 BottomSheet 동작 로그를 완료 후 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 계정 BottomSheet 동작 로그를 콘솔에 기록합니다.',
    );
    if (!mounted) return;
    trace.log('before ${_calendarAccountDiagnostics()}', progress: 0.18);
    HapticFeedback.selectionClick();

    try {
      await showSprintAccountSheet(
        context: context,
        store: _store,
      );
      if (!mounted) return;
      _store.ensureCalendarRangeFor(_monthAnchor, immediate: true);
      trace.log('after ${_calendarAccountDiagnostics()}', progress: 0.86);
      await trace.succeed('캘린더 연결 BottomSheet를 닫았습니다.');
      if (!mounted || !trace.developerMode) return;
      await trace.showSnapshotStatusDialog(
        context,
        title: '캘린더 연결',
        description: '계정 BottomSheet 동작의 debugPrint 코드를 복사할 수 있습니다.',
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '캘린더 연결 BottomSheet 처리에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || !trace.developerMode) return;
      await trace.showSnapshotStatusDialog(
        context,
        title: '캘린더 연결 오류',
        description: '실패 로그의 debugPrint 코드를 복사할 수 있습니다.',
        failure: true,
      );
    }
  }

  Widget _buildAccountEntry(
    BuildContext context, {
    required Duration duration,
    bool compact = false,
    bool extreme = false,
  }) {
    final state = _store.calendarState;
    final profileCount = _store.calendarProfiles.length;
    final enabled =
        _store.initialized && state != SprintCalendarConnectionState.syncing;
    final errorState = state == SprintCalendarConnectionState.failed ||
        state == SprintCalendarConnectionState.reauthenticationRequired;
    final cs = Theme.of(context).colorScheme;

    if (extreme) {
      return AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: errorState
              ? cs.errorContainer.withOpacity(.32)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: errorState
                ? cs.error.withOpacity(.26)
                : cs.outlineVariant.withOpacity(.58),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: enabled ? _openAccountSheet : null,
            onLongPress: _showAccountDeveloperStatus,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  Icon(
                    errorState
                        ? Icons.event_busy_outlined
                        : Icons.event_available_outlined,
                    color: errorState ? cs.error : cs.primary,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '캘린더 연결',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: duration,
                    child: Text(
                      _calendarStateLabel(state),
                      key: ValueKey<SprintCalendarConnectionState>(state),
                      style: TextStyle(
                        color: errorState ? cs.error : cs.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: errorState
            ? cs.errorContainer.withOpacity(.32)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: errorState
              ? cs.error.withOpacity(.26)
              : cs.outlineVariant.withOpacity(.58),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? _openAccountSheet : null,
          onLongPress: _showAccountDeveloperStatus,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 8 : 12,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: compact ? 34 : 42,
                  height: compact ? 34 : 42,
                  decoration: BoxDecoration(
                    color: errorState
                        ? cs.errorContainer
                        : cs.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: duration,
                    child: Icon(
                      profileCount > 1
                          ? Icons.calendar_view_month_rounded
                          : Icons.event_available_outlined,
                      key: ValueKey<int>(profileCount),
                      color: errorState
                          ? cs.onErrorContainer
                          : cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '캘린더 연결',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      SizedBox(height: compact ? 2 : 3),
                      AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Text(
                          _calendarAccountSubtitle,
                          key: ValueKey<String>(_calendarAccountSubtitle),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: duration,
                  child: state == SprintCalendarConnectionState.syncing
                      ? const SizedBox(
                          key: ValueKey<String>('hq-calendar-account-syncing'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          key: const ValueKey<String>(
                            'hq-calendar-account-ready',
                          ),
                          color: enabled
                              ? cs.onSurfaceVariant
                              : cs.outline.withOpacity(.5),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _itemColor(BuildContext context, _HeadquarterCalendarItem item) {
    final cs = Theme.of(context).colorScheme;
    if (item.isTask) {
      switch (item.priority) {
        case SprintTaskPriority.high:
          return cs.error;
        case SprintTaskPriority.normal:
          return googleEventColor(item.colorId, cs.primary);
        case SprintTaskPriority.low:
          return cs.secondary;
        case null:
          return cs.secondary;
      }
    }
    return googleEventColor(item.colorId, cs.secondary);
  }

  Future<void> _showCalendarDeveloperStatus() async {
    HeadquarterCalendarSideDockDiagnostics.log(
      'dashboard_status date=${_selectedDay.toIso8601String()} events=${_selectedItems.length} profiles=${_store.calendarProfiles.length} state=${_store.calendarState.name}',
    );
    await HeadquarterCalendarSideDockDiagnostics.showStatus(
      context,
      title: '본사 일정 상태',
      description:
          '선택 날짜 ${_selectedDay.month}월 ${_selectedDay.day}일 · 일정 ${_selectedItems.length}개 · 연결 ${_store.calendarProfiles.length}개의 debugPrint 코드를 복사할 수 있습니다.',
    );
  }

  List<HeadquarterCalendarDockEntry> _buildDockEntries() {
    return _selectedItems
        .map(
          (item) => HeadquarterCalendarDockEntry(
            id: item.id,
            title: item.title,
            subtitle: '${_rangeLabel(item)} · ${item.profileLabel}',
            icon: item.icon,
            color: _itemColor(context, item),
            task: item.isTask,
            readOnly: !item.isTask && !item.editable,
            onTap: () => _openItem(item),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _openFullScheduleDock() async {
    if (_selectedItems.isEmpty) return;
    final controller = CommonSideDockPresentationController();
    HeadquarterCalendarSideDockDiagnostics.log(
      'preview_more_open date=${_selectedDay.toIso8601String()} count=${_selectedItems.length}',
    );
    try {
      await showHeadquarterCalendarSideDock(
        context: context,
        selectedDay: _selectedDay,
        listenable: _store,
        entriesBuilder: _buildDockEntries,
        onAdd: _openCreate,
        presentationController: controller,
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final events = _selectedItems;
    final summary = _monthSummary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 720.0;
        final compact = viewportHeight < 650;
        final ultra = viewportHeight < 540;
        final extreme = viewportHeight < 470;
        final outerPadding = extreme
            ? 5.0
            : ultra
                ? 8.0
                : compact
                    ? 10.0
                    : 14.0;
        final gap = extreme
            ? 3.0
            : ultra
                ? 5.0
                : compact
                    ? 7.0
                    : 10.0;
        final previewLimit = extreme
            ? 0
            : ultra
                ? 1
                : compact
                    ? 1
                    : viewportHeight >= 760
                        ? 3
                        : 2;
        final previewEvents = events.take(previewLimit).toList(growable: false);
        final hiddenCount = events.length - previewEvents.length;
        final accountHeight = widget.showAccountEntry
            ? extreme
                ? 40.0
                : ultra
                    ? 52.0
                    : compact
                        ? 58.0
                        : 66.0
            : 0.0;
        final headerHeight = 40.0;
        final monthHeight = extreme ? 40.0 : 44.0;
        final weekdaysHeight = extreme ? 15.0 : 18.0;
        final selectedHeaderHeight = extreme ? 20.0 : 24.0;
        final previewHeight = events.isEmpty
            ? extreme
                ? 40.0
                : ultra
                    ? 44.0
                    : 50.0
            : (previewEvents.length * (ultra ? 44.0 : 50.0)) +
                (hiddenCount > 0
                    ? extreme
                        ? 36.0
                        : ultra
                            ? 38.0
                            : 42.0
                    : 0.0);
        final gapCount = widget.showAccountEntry ? 6 : 5;
        final reserved = outerPadding * 2 +
            headerHeight +
            accountHeight +
            monthHeight +
            weekdaysHeight +
            selectedHeaderHeight +
            previewHeight +
            (gap * gapCount);
        final gridHeight = (viewportHeight - reserved)
            .clamp(extreme ? 0.0 : 72.0, 330.0)
            .toDouble();
        final layoutLog =
            'layout height=${viewportHeight.toStringAsFixed(1)} compact=$compact ultra=$ultra extreme=$extreme preview=${previewEvents.length} hidden=$hiddenCount grid=${gridHeight.toStringAsFixed(1)}';
        if (_lastLayoutLog != layoutLog) {
          _lastLayoutLog = layoutLog;
          HeadquarterCalendarSideDockDiagnostics.log(layoutLog);
        }

        final content = Container(
          padding: EdgeInsets.all(outerPadding),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: headerHeight,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.calendar_month_rounded,
                        color: tokens.onAccentContainer,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '일정',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.15,
                            ),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: DevAuth.devModeEnabled,
                      builder: (context, enabled, child) {
                        if (!enabled) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            onPressed: _showCalendarDeveloperStatus,
                            tooltip: '상태',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.bug_report_outlined,
                              color: tokens.textSecondary,
                              size: 18,
                            ),
                          ),
                        );
                      },
                    ),
                    if (widget.headerTrailing != null) widget.headerTrailing!,
                  ],
                ),
              ),
              SizedBox(height: gap),
              if (widget.showAccountEntry) ...[
                SizedBox(
                  height: accountHeight,
                  child: _buildAccountEntry(
                    context,
                    duration: duration,
                    compact: compact,
                    extreme: extreme,
                  ),
                ),
                SizedBox(height: gap),
              ],
              SizedBox(
                height: monthHeight,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _moveMonth(-1),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_visibleMonth.year}년 ${_visibleMonth.month.toString().padLeft(2, '0')}월',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _moveMonth(1),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    IconButton(
                      onPressed: _refreshing ? null : _refresh,
                      tooltip: '일정 갱신',
                      visualDensity: VisualDensity.compact,
                      icon: reduceMotion
                          ? Icon(
                              _refreshing
                                  ? Icons.sync_rounded
                                  : Icons.refresh_rounded,
                            )
                          : RotationTransition(
                              turns: _refreshController,
                              child: Icon(
                                _refreshing
                                    ? Icons.sync_rounded
                                    : Icons.refresh_rounded,
                              ),
                            ),
                    ),
                    IconButton(
                      onPressed: _store.initialized ? _openCreate : null,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add_circle_rounded),
                      tooltip: '일정 추가',
                    ),
                  ],
                ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: weekdaysHeight,
                child: Row(
                  children: _weekdays
                      .map(
                        (day) => Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w900,
                                fontSize: compact ? 11 : 12,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              SizedBox(height: gap * .6),
              SizedBox(
                height: gridHeight,
                child: (_store.initializing || !_store.initialized) &&
                        _initializationError == null
                    ? const Center(child: CircularProgressIndicator())
                    : _initializationError != null
                        ? _ErrorBox(
                            text: '캘린더 연결 정보를 불러오지 못했습니다.',
                            compact: compact,
                            onRetry: () {
                              debugPrint(
                                '[HeadquarterCalendar] retry initialization error=$_initializationError',
                              );
                              if (_initializationStack != null) {
                                debugPrint('$_initializationStack');
                              }
                              setState(() {
                                _initializationError = null;
                                _initializationStack = null;
                              });
                              unawaited(_initialize());
                            },
                          )
                        : _buildCalendarGrid(
                            summary,
                            height: gridHeight,
                            compact: compact,
                          ),
              ),
              SizedBox(height: gap),
              SizedBox(
                height: selectedHeaderHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedDay.month}월 ${_selectedDay.day}일 ${_weekdays[_selectedDay.weekday % 7]}요일',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        '${events.length}개',
                        key: ValueKey<int>(events.length),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: gap * .6),
              SizedBox(
                height: previewHeight,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    if (reduceMotion) return child;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .035),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Align(
                    key: ValueKey<String>(
                      '${_dateKey(_selectedDay)}-${events.map((event) => event.id).join('|')}',
                    ),
                    alignment: Alignment.topCenter,
                    child: _buildPreviewArea(
                      events: events,
                      previewEvents: previewEvents,
                      hiddenCount: hiddenCount,
                      compact: compact,
                      ultra: ultra,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

        if (!widget.fillViewport || !constraints.maxHeight.isFinite) {
          return content;
        }
        return SizedBox.expand(child: content);
      },
    );
  }

  Widget _buildPreviewArea({
    required List<_HeadquarterCalendarItem> events,
    required List<_HeadquarterCalendarItem> previewEvents,
    required int hiddenCount,
    required bool compact,
    required bool ultra,
  }) {
    if (_store.calendarProfiles.isEmpty && _store.initialized) {
      return _ConnectionBox(onRefresh: _refresh, compact: compact);
    }
    if (events.isEmpty) {
      return _EmptyBox(onAdd: _openCreate, compact: compact);
    }
    return Column(
      key: ValueKey<String>(
        '${_dateKey(_selectedDay)}-${events.map((event) => event.id).join('|')}',
      ),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final event in previewEvents)
          _EventTile(
            event: event,
            color: _itemColor(context, event),
            onTap: () => _openItem(event),
            compact: true,
            ultra: ultra,
          ),
        if (hiddenCount > 0)
          _MoreEventsButton(
            hiddenCount: hiddenCount,
            onTap: _openFullScheduleDock,
            compact: compact,
          ),
      ],
    );
  }

  Widget _buildCalendarGrid(
    Map<String, _DaySummary> summary, {
    required double height,
    required bool compact,
  }) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    final days = List<DateTime>.generate(
      42,
      (index) => start.add(Duration(days: index)),
    );
    final dense = (height / 6) < 28;
    return Column(
      children: List<Widget>.generate(6, (weekIndex) {
        return Expanded(
          child: Row(
            children: List<Widget>.generate(7, (weekdayIndex) {
              final index = weekIndex * 7 + weekdayIndex;
              final day = days[index];
              final daySummary = summary[_dateKey(day)];
              final selected = _sameDay(day, _selectedDay);
              final today = _sameDay(day, DateTime.now());
              final inMonth = day.month == _visibleMonth.month &&
                  day.year == _visibleMonth.year;
              return Expanded(
                child: _DayCell(
                  day: day.day,
                  count: daySummary?.count ?? 0,
                  important: daySummary?.important ?? false,
                  selected: selected,
                  today: today,
                  inMonth: inMonth,
                  compact: compact,
                  dense: dense,
                  onTap: () => _selectDay(day),
                ),
              );
            }, growable: false),
          ),
        );
      }, growable: false),
    );
  }

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _dateLabel(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

  static String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  static String _rangeLabel(_HeadquarterCalendarItem item) {
    if (item.allDay) {
      if (_sameDay(item.start, item.lastDay)) {
        return '${_dateLabel(item.start)} · 종일';
      }
      return '${_dateLabel(item.start)} ~ ${_dateLabel(item.lastDay)} · 종일';
    }
    if (_sameDay(item.start, item.end)) {
      return '${_dateLabel(item.start)} · ${_timeLabel(item.start)}~${_timeLabel(item.end)}';
    }
    return '${_dateLabel(item.start)} ${_timeLabel(item.start)} ~ ${_dateLabel(item.end)} ${_timeLabel(item.end)}';
  }
}

class _HeadquarterCalendarItem {
  const _HeadquarterCalendarItem({
    required this.id,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    required this.allDay,
    required this.profileLabel,
    required this.icon,
    required this.colorId,
    required this.isTask,
    required this.important,
    required this.editable,
    this.priority,
    this.taskId,
    this.externalEventId,
    this.projectName = '',
  });

  factory _HeadquarterCalendarItem.task({
    required SprintTask task,
    required String profileLabel,
    required String projectName,
    required IconData projectIcon,
    required String? projectColorId,
  }) {
    return _HeadquarterCalendarItem(
      id: 'task:${task.id}',
      title: task.title,
      description: task.description,
      start: task.startDate,
      end: task.endDate.add(const Duration(days: 1)),
      allDay: true,
      profileLabel: profileLabel,
      icon: projectIcon,
      colorId: projectColorId,
      isTask: true,
      important: task.priority == SprintTaskPriority.high,
      editable: true,
      priority: task.priority,
      taskId: task.id,
      projectName: projectName,
    );
  }

  factory _HeadquarterCalendarItem.external({
    required SprintExternalEvent event,
    required String profileLabel,
    required bool editable,
  }) {
    return _HeadquarterCalendarItem(
      id: 'external:${event.id}',
      title: event.title,
      description: event.description,
      start: event.start,
      end: event.end,
      allDay: event.allDay,
      profileLabel: profileLabel,
      icon: Icons.event_note_rounded,
      colorId: event.colorId,
      isTask: false,
      important: false,
      editable: editable,
      externalEventId: event.id,
    );
  }

  final String id;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String profileLabel;
  final IconData icon;
  final String? colorId;
  final bool isTask;
  final bool important;
  final bool editable;
  final SprintTaskPriority? priority;
  final String? taskId;
  final String? externalEventId;
  final String projectName;

  DateTime get lastDay {
    final value = allDay ? end.subtract(const Duration(days: 1)) : end;
    return DateTime(value.year, value.month, value.day);
  }

  bool spans(DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    final first = DateTime(start.year, start.month, start.day);
    return !day.isBefore(first) && !day.isAfter(lastDay);
  }
}

class _DaySummary {
  const _DaySummary({this.count = 0, this.important = false});

  final int count;
  final bool important;
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.count,
    required this.important,
    required this.selected,
    required this.today,
    required this.inMonth,
    required this.compact,
    required this.dense,
    required this.onTap,
  });

  final int day;
  final int count;
  final bool important;
  final bool selected;
  final bool today;
  final bool inMonth;
  final bool compact;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = selected
        ? cs.onPrimary
        : inMonth
            ? cs.onSurface
            : cs.onSurfaceVariant.withOpacity(.45);
    final background = selected
        ? cs.primary
        : today
            ? cs.primaryContainer.withOpacity(.45)
            : tokens.transparent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.all(dense ? .5 : compact ? 1 : 2),
        padding: dense
            ? EdgeInsets.zero
            : EdgeInsets.fromLTRB(3, compact ? 3 : 5, 3, compact ? 2 : 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: today && !selected
              ? Border.all(color: cs.primary.withOpacity(.45))
              : null,
        ),
        child: dense
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected || today
                          ? FontWeight.w900
                          : FontWeight.w700,
                      fontSize: 9,
                      height: 1,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      bottom: 1,
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.onPrimary
                              : important
                                  ? cs.error
                                  : cs.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                children: [
                  Text(
                    '$day',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: selected || today
                          ? FontWeight.w900
                          : FontWeight.w700,
                      fontSize: compact ? 11 : 12,
                    ),
                  ),
                  const Spacer(),
                  if (count > 0)
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      constraints: BoxConstraints(minWidth: compact ? 18 : 20),
                      height: compact ? 15 : 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.onPrimary.withOpacity(.2)
                            : important
                                ? cs.errorContainer
                                : cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: TextStyle(
                          color: selected
                              ? cs.onPrimary
                              : important
                                  ? cs.onErrorContainer
                                  : cs.onSecondaryContainer,
                          fontSize: compact ? 8 : 9,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                    )
                  else
                    SizedBox(height: compact ? 15 : 18),
                ],
              ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.ultra = false,
  });

  final _HeadquarterCalendarItem event;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final bool ultra;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    return Padding(
      padding: EdgeInsets.only(bottom: ultra ? 3 : compact ? 4 : 7),
      child: Material(
        color: tokens.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 11,
              vertical: ultra ? 5 : compact ? 7 : 11,
            ),
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withOpacity(.07), cs.surface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(.2)),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  width: ultra ? 28 : compact ? 30 : 34,
                  height: ultra ? 28 : compact ? 30 : 34,
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(compact ? 9 : 11),
                  ),
                  child: Icon(event.icon, color: color, size: compact ? 17 : 19),
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_HeadquarterCalendarCardState._rangeLabel(event)} · ${event.profileLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.isTask)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: color,
                      size: 17,
                    ),
                  )
                else if (!event.editable)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: cs.onSurfaceVariant,
                      size: 17,
                    ),
                  ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreEventsButton extends StatefulWidget {
  const _MoreEventsButton({
    required this.hiddenCount,
    required this.onTap,
    required this.compact,
  });

  final int hiddenCount;
  final Future<void> Function() onTap;
  final bool compact;

  @override
  State<_MoreEventsButton> createState() => _MoreEventsButtonState();
}

class _MoreEventsButtonState extends State<_MoreEventsButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return FocusableActionDetector(
      onShowHoverHighlight: (value) {
        if (mounted) setState(() => _hovered = value);
      },
      onShowFocusHighlight: (value) {
        if (mounted) setState(() => _focused = value);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
          curve: CommonUiMotion.standard,
          scale: _pressed ? .98 : 1,
          child: AnimatedContainer(
            duration: duration,
            curve: CommonUiMotion.enter,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 12,
              vertical: widget.compact ? 7 : 9,
            ),
            decoration: BoxDecoration(
              color: _hovered ? tokens.surfaceSelected : tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused
                    ? tokens.focusRing
                    : _hovered
                        ? tokens.accent.withOpacity(.36)
                        : tokens.borderSubtle,
                width: _focused ? 2 : 1,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: tokens.shadow.withOpacity(tokens.isDark ? .22 : .08),
                        blurRadius: 9,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                Icon(Icons.view_agenda_outlined, color: tokens.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '+ ${widget.hiddenCount}개 일정 더 보기',
                    style: TextStyle(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                AnimatedSlide(
                  duration: duration,
                  offset: _hovered ? const Offset(.12, 0) : Offset.zero,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: tokens.textSecondary,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.onAdd, this.compact = false});

  final VoidCallback onAdd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '선택한 날짜에 일정이 없습니다.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('일정 추가'),
          ),
        ],
      ),
    );
  }
}

class _ConnectionBox extends StatelessWidget {
  const _ConnectionBox({required this.onRefresh, this.compact = false});

  final VoidCallback onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: cs.primary, size: 19),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '연결된 캘린더가 없습니다.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text, required this.onRetry, this.compact = false});

  final String text;
  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('재시도')),
        ],
      ),
    );
  }
}
