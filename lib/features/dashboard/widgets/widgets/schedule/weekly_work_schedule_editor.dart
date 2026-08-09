import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../app/init/work_schedule_prefs.dart';
import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../account/applications/user_state.dart';
import '../../../../account/domain/models/session_account.dart';

final ValueNotifier<int> _weeklyWorkScheduleRevision = ValueNotifier<int>(0);

class WeeklyWorkScheduleEditor extends StatefulWidget {
  const WeeklyWorkScheduleEditor({
    super.key,
    required this.source,
    this.initiallyExpanded = false,
  });

  final String source;
  final bool initiallyExpanded;

  @override
  State<WeeklyWorkScheduleEditor> createState() =>
      _WeeklyWorkScheduleEditorState();
}

class _WeeklyWorkScheduleEditorState extends State<WeeklyWorkScheduleEditor> {
  static const List<String> _days = WorkSchedulePrefs.days;

  bool _loading = true;
  bool _editorExpanded = false;
  bool _sharedSyncQueued = false;
  String? _savingDay;
  late String _selectedDay;
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  Set<String> _breakDays = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedDay = _dayForDate(DateTime.now());
    _editorExpanded = widget.initiallyExpanded;
    _weeklyWorkScheduleRevision.addListener(_handleSharedScheduleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSchedule(reason: 'initial');
    });
  }

  @override
  void dispose() {
    _weeklyWorkScheduleRevision.removeListener(_handleSharedScheduleChanged);
    super.dispose();
  }

  void _handleSharedScheduleChanged() {
    if (!mounted || _loading || _savingDay != null || _sharedSyncQueued) {
      return;
    }
    _sharedSyncQueued = true;
    debugPrint(
      '[WeeklyWorkScheduleEditor] source=${widget.source} event=shared_schedule_sync_queued revision=${_weeklyWorkScheduleRevision.value}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sharedSyncQueued = false;
      if (!mounted || _loading || _savingDay != null) return;
      _loadSchedule(reason: 'shared_editor_change');
    });
  }

  void _broadcastSharedScheduleChange() {
    _weeklyWorkScheduleRevision.value = _weeklyWorkScheduleRevision.value + 1;
    debugPrint(
      '[WeeklyWorkScheduleEditor] source=${widget.source} event=shared_schedule_changed revision=${_weeklyWorkScheduleRevision.value}',
    );
  }

  String _dayForDate(DateTime date) => _days[date.weekday - 1];

  String _formatTime(TimeOfDay? value) {
    if (value == null) return '-';
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime date) {
    final day = _dayForDate(date);
    return '${date.year}년 ${date.month}월 ${date.day}일 · $day요일';
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  List<String> _cachedStringList(dynamic raw) {
    if (raw is Iterable) {
      return WorkSchedulePrefs.normalizeDayList(
        raw.map((value) => value.toString()),
      );
    }
    if (raw is Map) {
      return <String>[
        for (final day in _days)
          if (raw[day] == true) day,
      ];
    }
    return const <String>[];
  }

  Set<String> _workingDays(
    Map<String, TimeOfDay?> startMap,
    Map<String, TimeOfDay?> endMap,
  ) {
    return <String>{
      for (final day in _days)
        if (startMap[day] != null && endMap[day] != null) day,
    };
  }

  void _log(
    String event, {
    String? day,
    bool? success,
  }) {
    final selected = day ?? _selectedDay;
    final startConfigured = _startByDay[selected] != null;
    final endConfigured = _endByDay[selected] != null;
    final hasBreak = _breakDays.contains(selected);
    debugPrint(
      '[WeeklyWorkScheduleEditor] source=${widget.source} event=$event selectedDay=$selected editorExpanded=$_editorExpanded saving=${_savingDay != null} startConfigured=$startConfigured endConfigured=$endConfigured hasBreak=$hasBreak${success == null ? '' : ' success=$success'}',
    );
  }

  Future<void> _loadSchedule({required String reason}) async {
    if (mounted) {
      setState(() => _loading = true);
    }

    final userState = context.read<UserState>();
    final session = userState.session;
    final user = session is UserSessionAccount ? session.user : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final cached = _decodeJsonMap(prefs.getString('cachedUserJson') ?? '');
    final fixedHolidays = prefs.getStringList('fixedHolidays') ??
        user?.fixedHolidays ??
        _cachedStringList(cached['fixedHolidays']);

    final startRaw = (prefs.getString(WorkSchedulePrefs.startMapKey) ?? '').trim();
    final endRaw = (prefs.getString(WorkSchedulePrefs.endMapKey) ?? '').trim();

    Map<String, TimeOfDay?> startMap;
    if (startRaw.isNotEmpty) {
      startMap = WorkSchedulePrefs.readDayTimeMapFromPrefs(
        prefs,
        WorkSchedulePrefs.startMapKey,
      );
    } else if (user != null) {
      startMap = WorkSchedulePrefs.resolveStartMap(user);
    } else {
      startMap = WorkSchedulePrefs.fillAllDays(
        WorkSchedulePrefs.parseHHmm(prefs.getString('startTime')),
        excludedDays: fixedHolidays.toSet(),
      );
    }

    Map<String, TimeOfDay?> endMap;
    if (endRaw.isNotEmpty) {
      endMap = WorkSchedulePrefs.readDayTimeMapFromPrefs(
        prefs,
        WorkSchedulePrefs.endMapKey,
      );
    } else if (user != null) {
      endMap = WorkSchedulePrefs.resolveEndMap(user);
    } else {
      endMap = WorkSchedulePrefs.fillAllDays(
        WorkSchedulePrefs.parseHHmm(prefs.getString('endTime')),
        excludedDays: fixedHolidays.toSet(),
      );
    }

    final workingDays = _workingDays(startMap, endMap);
    final fallbackBreakDays = user?.breakDays ??
        (cached.containsKey('breakDays')
            ? _cachedStringList(cached['breakDays'])
            : workingDays.toList(growable: false));
    final breakDays = WorkSchedulePrefs.readBreakDaysFromPrefs(
      prefs,
      fallback: fallbackBreakDays,
    );
    final normalizedBreakDays = WorkSchedulePrefs.normalizeBreakDaysForWorkingMap(
      breakDays: breakDays,
      startByDay: startMap,
      endByDay: endMap,
    ).toSet();

    if (!mounted) return;
    setState(() {
      _startByDay = WorkSchedulePrefs.normalizeDayTimeMap(startMap);
      _endByDay = WorkSchedulePrefs.normalizeDayTimeMap(endMap);
      _breakDays = normalizedBreakDays;
      _loading = false;
    });
    _log('loaded_$reason');
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _saveWeeklyTime({
    required String day,
    required TimeOfDay? startTime,
    required TimeOfDay? endTime,
  }) async {
    if (_savingDay != null) return;
    if ((startTime == null) != (endTime == null)) {
      _showSnack('출근/퇴근 시간을 모두 입력하거나 모두 비워 주세요.');
      return;
    }

    final wasHoliday = _startByDay[day] == null && _endByDay[day] == null;
    setState(() => _savingDay = day);
    _log('save_time_start', day: day);

    final ok = await context
        .read<UserState>()
        .setCurrentUserWeekdayWorkTimeLocalOnly(
          day: day,
          startTime: startTime,
          endTime: endTime,
        );

    if (!mounted) return;
    if (ok) {
      _broadcastSharedScheduleChange();
      setState(() {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = startTime;
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = endTime;
        final nextBreakDays = <String>{..._breakDays};
        if (startTime == null && endTime == null) {
          nextBreakDays.remove(day);
        } else if (wasHoliday) {
          nextBreakDays.add(day);
        }
        _breakDays = nextBreakDays;
        _savingDay = null;
      });
      _log('save_time_complete', day: day, success: true);
      _showSnack(
        startTime == null && endTime == null
            ? '$day요일이 휴무로 저장되었습니다.'
            : '$day요일 근무 시간이 저장되었습니다.',
      );
      return;
    }

    setState(() => _savingDay = null);
    _log('save_time_complete', day: day, success: false);
    await _loadSchedule(reason: 'save_time_failure');
    if (!mounted) return;
    _showSnack('근무 시간 저장에 실패했습니다.');
  }

  Future<void> _setHoliday(String day, bool value) async {
    if (_savingDay != null) return;
    HapticFeedback.lightImpact();
    if (value) {
      await _saveWeeklyTime(day: day, startTime: null, endTime: null);
      return;
    }
    await _saveWeeklyTime(
      day: day,
      startTime: _startByDay[day] ?? const TimeOfDay(hour: 9, minute: 0),
      endTime: _endByDay[day] ?? const TimeOfDay(hour: 18, minute: 0),
    );
  }

  Future<void> _toggleBreakDay(String day, bool value) async {
    if (_savingDay != null) return;
    if (_startByDay[day] == null || _endByDay[day] == null) {
      _showSnack('근무 시간이 있는 요일만 휴게를 설정할 수 있습니다.');
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _savingDay = day);
    _log('save_break_start', day: day);

    final ok = await context.read<UserState>().setCurrentUserBreakDayLocalOnly(
      day: day,
      hasBreak: value,
    );

    if (!mounted) return;
    if (ok) {
      _broadcastSharedScheduleChange();
      setState(() {
        final next = <String>{..._breakDays};
        if (value) {
          next.add(day);
        } else {
          next.remove(day);
        }
        _breakDays = next;
        _savingDay = null;
      });
      _log('save_break_complete', day: day, success: true);
      _showSnack(value ? '$day요일 휴게가 설정되었습니다.' : '$day요일 휴게가 해제되었습니다.');
      return;
    }

    setState(() => _savingDay = null);
    _log('save_break_complete', day: day, success: false);
    await _loadSchedule(reason: 'save_break_failure');
    if (!mounted) return;
    _showSnack('휴게 설정 저장에 실패했습니다.');
  }

  Future<void> _pickWeeklyTime({
    required String day,
    required bool isStart,
  }) async {
    if (_savingDay != null) return;
    HapticFeedback.selectionClick();

    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ??
        (isStart
            ? const TimeOfDay(hour: 9, minute: 0)
            : const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '출근 시간 선택 ($day)' : '퇴근 시간 선택 ($day)',
      confirmText: '확인',
      cancelText: '취소',
    );

    if (!mounted || picked == null) return;
    final currentStart = _startByDay[day];
    final currentEnd = _endByDay[day];
    final nextStart = isStart
        ? picked
        : currentStart ?? const TimeOfDay(hour: 9, minute: 0);
    final nextEnd = isStart
        ? currentEnd ?? const TimeOfDay(hour: 18, minute: 0)
        : picked;
    await _saveWeeklyTime(
      day: day,
      startTime: nextStart,
      endTime: nextEnd,
    );
  }

  void _toggleEditor() {
    HapticFeedback.selectionClick();
    setState(() {
      _editorExpanded = !_editorExpanded;
      if (_editorExpanded) {
        _selectedDay = _dayForDate(DateTime.now());
      }
    });
    _log(_editorExpanded ? 'editor_open' : 'editor_close');
  }

  void _selectDay(String day) {
    if (_selectedDay == day || _savingDay != null) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedDay = day);
    _log('editor_day_select', day: day);
  }

  Future<void> _showDeveloperStatus() async {
    final now = DateTime.now();
    final today = _dayForDate(now);
    final todayStart = _startByDay[today];
    final todayEnd = _endByDay[today];
    final selectedStart = _startByDay[_selectedDay];
    final selectedEnd = _endByDay[_selectedDay];
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '근무 일정 상태',
      initialMessage: '공용 근무 일정 편집기 상태를 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    trace.log('component=weekly_work_schedule_editor', progress: 0.12);
    trace.log('source=${widget.source}', progress: 0.18);
    trace.log('today=$today', progress: 0.27);
    trace.log('todayStartConfigured=${todayStart != null}', progress: 0.36);
    trace.log('todayEndConfigured=${todayEnd != null}', progress: 0.45);
    trace.log('todayHasBreak=${_breakDays.contains(today)}', progress: 0.54);
    trace.log('editorExpanded=$_editorExpanded', progress: 0.63);
    trace.log('selectedEditDay=$_selectedDay', progress: 0.71);
    trace.log('selectedStartConfigured=${selectedStart != null}', progress: 0.79);
    trace.log('selectedEndConfigured=${selectedEnd != null}', progress: 0.86);
    trace.log('saving=${_savingDay != null}', progress: 0.92);
    trace.log('syncMode=shared_editor_revision', progress: 0.95);
    trace.log('scheduleStorage=local_only', progress: 0.97);
    await trace.succeed('공용 근무 일정 편집기 상태 확인을 완료했습니다.');
  }

  _ScheduleStatus _statusOf(String day) {
    final start = _startByDay[day];
    final end = _endByDay[day];
    if (start == null && end == null) return _ScheduleStatus.holiday;
    if ((start == null) != (end == null)) return _ScheduleStatus.partial;
    return _ScheduleStatus.working;
  }

  Widget _animatedContent({
    required Widget child,
    required Object key,
  }) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (item, animation) {
        if (reduceMotion) return item;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(animation),
            child: item,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<Object>(key), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final now = DateTime.now();
    final today = _dayForDate(now);

    final content = _loading
        ? KeyedSubtree(
            key: const ValueKey<String>('schedule_loading'),
            child: _ScheduleLoading(tokens: tokens),
          )
        : KeyedSubtree(
            key: const ValueKey<String>('schedule_content'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(now),
                            style: text.labelLarge?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '오늘 근무 일정',
                            style: text.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ScheduleStatusBadge(
                      status: _statusOf(today),
                      tokens: tokens,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _animatedContent(
                  key:
                      'today_${_statusOf(today).name}_${_formatTime(_startByDay[today])}_${_formatTime(_endByDay[today])}_${_breakDays.contains(today)}',
                  child: _TodayScheduleSummary(
                    status: _statusOf(today),
                    startTime: _startByDay[today],
                    endTime: _endByDay[today],
                    hasBreak: _breakDays.contains(today),
                    formatTime: _formatTime,
                    onEdit: _toggleEditor,
                  ),
                ),
                if (_editorExpanded) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: tokens.borderSubtle),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '요일별 일정 수정',
                          style: text.labelLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            _savingDay == null ? _toggleEditor : null,
                        icon: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 18,
                        ),
                        label: const Text('완료'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _WeekdaySelector(
                    days: _days,
                    selectedDay: _selectedDay,
                    saving: _savingDay != null,
                    reduceMotion: reduceMotion,
                    onSelect: _selectDay,
                  ),
                  const SizedBox(height: 12),
                  _animatedContent(
                    key:
                        'editor_${_selectedDay}_${_statusOf(_selectedDay).name}_${_formatTime(_startByDay[_selectedDay])}_${_formatTime(_endByDay[_selectedDay])}_${_breakDays.contains(_selectedDay)}_${_savingDay == _selectedDay}',
                    child: _ScheduleEditor(
                      day: _selectedDay,
                      status: _statusOf(_selectedDay),
                      startTime: _startByDay[_selectedDay],
                      endTime: _endByDay[_selectedDay],
                      hasBreak: _breakDays.contains(_selectedDay),
                      isSaving: _savingDay == _selectedDay,
                      formatTime: _formatTime,
                      onPickStart: () => _pickWeeklyTime(
                        day: _selectedDay,
                        isStart: true,
                      ),
                      onPickEnd: () => _pickWeeklyTime(
                        day: _selectedDay,
                        isStart: false,
                      ),
                      onHolidayChanged: (value) =>
                          _setHoliday(_selectedDay, value),
                      onBreakChanged: (value) =>
                          _toggleBreakDay(_selectedDay, value),
                    ),
                  ),
                ],
              ],
            ),
          );

    return Semantics(
      container: true,
      label: '오늘 근무 일정',
      child: Material(
        color: tokens.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            debugPrint(
              '[WeeklyWorkScheduleEditor] source=${widget.source} event=developer_status_request',
            );
            _showDeveloperStatus();
          },
          child: AnimatedSize(
            duration:
                reduceMotion ? Duration.zero : CommonUiMotion.component,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (item, animation) {
                  if (reduceMotion) return item;
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.025),
                        end: Offset.zero,
                      ).animate(animation),
                      child: item,
                    ),
                  );
                },
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ScheduleStatus { working, holiday, partial }

class _ScheduleLoading extends StatelessWidget {
  const _ScheduleLoading({required this.tokens});

  final CommonUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: tokens.accent,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              '오늘 근무 일정을 불러오는 중입니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleStatusBadge extends StatelessWidget {
  const _ScheduleStatusBadge({
    required this.status,
    required this.tokens,
  });

  final _ScheduleStatus status;
  final CommonUiTokens tokens;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color background;
    late final Color foreground;
    switch (status) {
      case _ScheduleStatus.working:
        label = '근무';
        background = tokens.successContainer;
        foreground = tokens.onSuccessContainer;
        break;
      case _ScheduleStatus.holiday:
        label = '휴무';
        background = tokens.surfaceSelected;
        foreground = tokens.textSecondary;
        break;
      case _ScheduleStatus.partial:
        label = '확인 필요';
        background = tokens.dangerContainer;
        foreground = tokens.onDangerContainer;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _TodayScheduleSummary extends StatelessWidget {
  const _TodayScheduleSummary({
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.hasBreak,
    required this.formatTime,
    required this.onEdit,
  });

  final _ScheduleStatus status;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final bool hasBreak;
  final String Function(TimeOfDay? value) formatTime;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    if (status == _ScheduleStatus.holiday) {
      return Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tokens.surfaceSelected,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.event_busy_rounded,
                    color: tokens.iconSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '오늘은 휴무일입니다.',
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('일정 수정'),
          ),
        ],
      );
    }

    if (status == _ScheduleStatus.partial) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.dangerContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: tokens.onDangerContainer,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '출근/퇴근 시간 중 일부가 비어 있습니다. 일정을 확인해 주세요.',
                    style: text.bodySmall?.copyWith(
                      color: tokens.onDangerContainer,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('지금 수정'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _TimePoint(
              icon: Icons.login_rounded,
              label: '출근',
              value: formatTime(startTime),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(height: 1, color: tokens.borderStrong),
              ),
            ),
            _TimePoint(
              icon: Icons.logout_rounded,
              label: '퇴근',
              value: formatTime(endTime),
              alignEnd: true,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: hasBreak
                    ? tokens.warningContainer
                    : tokens.surfaceSelected,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.coffee_rounded,
                    size: 15,
                    color: hasBreak
                        ? tokens.onWarningContainer
                        : tokens.iconSecondary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    hasBreak ? '휴게 있음' : '휴게 없음',
                    style: text.labelSmall?.copyWith(
                      color: hasBreak
                          ? tokens.onWarningContainer
                          : tokens.textSecondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('일정 수정'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TimePoint extends StatelessWidget {
  const _TimePoint({
    required this.icon,
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alignEnd) ...[
              Icon(icon, size: 15, color: tokens.iconSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              value,
              style: text.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (alignEnd) ...[
              const SizedBox(width: 5),
              Icon(icon, size: 15, color: tokens.iconSecondary),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: text.labelSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  const _WeekdaySelector({
    required this.days,
    required this.selectedDay,
    required this.saving,
    required this.reduceMotion,
    required this.onSelect,
  });

  final List<String> days;
  final String selectedDay;
  final bool saving;
  final bool reduceMotion;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final day in days)
              Semantics(
                button: true,
                selected: selectedDay == day,
                label: '$day요일',
                child: InkWell(
                  onTap: saving ? null : () => onSelect(day),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    curve: Curves.easeOutCubic,
                    width: constraints.maxWidth >= 300 ? 38 : 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selectedDay == day
                          ? tokens.accentContainer
                          : tokens.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedDay == day
                            ? tokens.accent
                            : tokens.borderSubtle,
                      ),
                    ),
                    child: Text(
                      day,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: selectedDay == day
                                ? tokens.onAccentContainer
                                : tokens.textSecondary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScheduleEditor extends StatelessWidget {
  const _ScheduleEditor({
    required this.day,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.hasBreak,
    required this.isSaving,
    required this.formatTime,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onHolidayChanged,
    required this.onBreakChanged,
  });

  final String day;
  final _ScheduleStatus status;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final bool hasBreak;
  final bool isSaving;
  final String Function(TimeOfDay? value) formatTime;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final Future<void> Function(bool value) onHolidayChanged;
  final Future<void> Function(bool value) onBreakChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final isHoliday = status == _ScheduleStatus.holiday;
    final hasPartial = status == _ScheduleStatus.partial;
    final effectiveBreak = hasBreak && !isHoliday && !hasPartial;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasPartial ? tokens.danger : tokens.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '$day요일',
                      style: text.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ScheduleStatusBadge(status: status, tokens: tokens),
                  ],
                ),
              ),
              if (isSaving)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: tokens.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ScheduleTimeButton(
                  label: '출근',
                  value: formatTime(startTime),
                  icon: Icons.login_rounded,
                  enabled: !isSaving,
                  onPressed: onPickStart,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScheduleTimeButton(
                  label: '퇴근',
                  value: formatTime(endTime),
                  icon: Icons.logout_rounded,
                  enabled: !isSaving,
                  onPressed: onPickEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ScheduleToggle(
                  label: '휴무',
                  icon: Icons.event_busy_rounded,
                  selected: isHoliday,
                  enabled: !isSaving,
                  selectedBackground: tokens.surfaceSelected,
                  selectedForeground: tokens.textPrimary,
                  onChanged: onHolidayChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScheduleToggle(
                  label: '휴게',
                  icon: Icons.coffee_rounded,
                  selected: effectiveBreak,
                  enabled: !isSaving && !isHoliday && !hasPartial,
                  selectedBackground: tokens.warningContainer,
                  selectedForeground: tokens.onWarningContainer,
                  onChanged: onBreakChanged,
                ),
              ),
            ],
          ),
          if (hasPartial) ...[
            const SizedBox(height: 9),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: tokens.dangerContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '출근/퇴근 시간을 모두 설정하거나 휴무로 전환해 주세요.',
                style: text.bodySmall?.copyWith(
                  color: tokens.onDangerContainer,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleTimeButton extends StatelessWidget {
  const _ScheduleTimeButton({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: enabled ? tokens.surface : tokens.surfaceDisabled,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: enabled ? tokens.iconSecondary : tokens.iconDisabled,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: enabled
                                ? tokens.textPrimary
                                : tokens.textDisabled,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleToggle extends StatelessWidget {
  const _ScheduleToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.selectedBackground,
    required this.selectedForeground,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final Color selectedBackground;
  final Color selectedForeground;
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = selected ? selectedForeground : tokens.textSecondary;
    return Material(
      color: tokens.transparent,
      child: InkWell(
        onTap: enabled ? () => onChanged(!selected) : null,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: Curves.easeOutCubic,
          height: 40,
          decoration: BoxDecoration(
            color: !enabled
                ? tokens.surfaceDisabled
                : selected
                    ? selectedBackground
                    : tokens.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: enabled ? foreground : tokens.iconDisabled,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: enabled ? foreground : tokens.textDisabled,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
