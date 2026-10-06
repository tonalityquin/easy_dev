import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../selector/application/dev_auth.dart';
import 'bulk_time_generator.dart';
import 'bulk_time_models.dart';

class BulkTimeEditor extends StatefulWidget {
  const BulkTimeEditor({
    super.key,
    required this.kind,
    required this.month,
    required this.userSeed,
    required this.rules,
    required this.currentClockIns,
    required this.currentClockOuts,
    required this.currentBreakTimes,
    required this.loadedClockIns,
    required this.loadedClockOuts,
    required this.loadedBreakTimes,
    required this.pendingDeleteClockInDays,
    required this.pendingDeleteClockOutDays,
    required this.pendingDeleteBreakDays,
    required this.onRulesChanged,
    required this.onApply,
    required this.onBack,
    required this.onDebugLog,
  });

  final BulkTimeEditorKind kind;
  final DateTime month;
  final String userSeed;
  final BulkTimeRules rules;
  final Map<int, String> currentClockIns;
  final Map<int, String> currentClockOuts;
  final Map<int, String> currentBreakTimes;
  final Map<int, String> loadedClockIns;
  final Map<int, String> loadedClockOuts;
  final Map<int, String> loadedBreakTimes;
  final Set<int> pendingDeleteClockInDays;
  final Set<int> pendingDeleteClockOutDays;
  final Set<int> pendingDeleteBreakDays;
  final ValueChanged<BulkTimeRules> onRulesChanged;
  final ValueChanged<BulkTimeApplyResult> onApply;
  final VoidCallback onBack;
  final ValueChanged<String> onDebugLog;

  @override
  State<BulkTimeEditor> createState() => _BulkTimeEditorState();
}

class _BulkTimeEditorState extends State<BulkTimeEditor> {
  late BulkTimeRules _rules;
  BulkDateScope _scope = BulkDateScope.month;
  final Set<int> _selectedDays = <int>{};
  bool _applying = false;

  CommonUiTokens get _tokens => CommonUiTheme.of(context);

  @override
  void initState() {
    super.initState();
    _rules = widget.rules;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onDebugLog(
        'editor_open kind=${widget.kind.name} month=${_monthKey(widget.month)} scope=${_scope.name}',
      );
      for (var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++) {
        final rule = _rules.ruleFor(weekday);
        widget.onDebugLog(
          'rule_snapshot weekday=$weekday enabled=${rule.enabled} in=${_formatMinutes(rule.clockInMinutes)} out=${_formatMinutes(rule.clockOutMinutes)} break=${_formatMinutes(rule.breakMinutes)}',
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant BulkTimeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rules != widget.rules) {
      _rules = widget.rules;
    }
  }

  String _monthKey(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}';
  }

  int get _daysInMonth {
    return BulkTimeGenerator.daysInMonth(widget.month);
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return '월';
      case DateTime.tuesday:
        return '화';
      case DateTime.wednesday:
        return '수';
      case DateTime.thursday:
        return '목';
      case DateTime.friday:
        return '금';
      case DateTime.saturday:
        return '토';
      case DateTime.sunday:
        return '일';
      default:
        return '-';
    }
  }

  String _formatMinutes(int minutes) {
    return BulkTimeGenerator.formatMinutes(minutes);
  }

  Future<int?> _pickMinutes(int initialMinutes) async {
    final initial = initialMinutes.clamp(0, 1439).toInt();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initial ~/ 60,
        minute: initial % 60,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return null;
    return picked.hour * 60 + picked.minute;
  }

  void _updateRule(int weekday, BulkWeekdayRule next) {
    setState(() {
      _rules = _rules.update(weekday, next);
    });
    widget.onRulesChanged(_rules);
    widget.onDebugLog(
      'rule_change weekday=$weekday enabled=${next.enabled} in=${_formatMinutes(next.clockInMinutes)} out=${_formatMinutes(next.clockOutMinutes)} break=${_formatMinutes(next.breakMinutes)}',
    );
  }

  void _syncWeekdaysFromMonday() {
    final source = _rules.ruleFor(DateTime.monday).copyWith(enabled: true);
    var next = _rules;
    for (var weekday = DateTime.monday;
        weekday <= DateTime.friday;
        weekday++) {
      next = next.update(weekday, source.copyWith(enabled: true));
    }
    setState(() => _rules = next);
    widget.onRulesChanged(next);
    HapticFeedback.selectionClick();
    widget.onDebugLog(
      'weekday_sync monday_to_friday in=${_formatMinutes(source.clockInMinutes)} out=${_formatMinutes(source.clockOutMinutes)} break=${_formatMinutes(source.breakMinutes)}',
    );
  }

  bool _hasInvalidAttendanceRule() {
    if (widget.kind != BulkTimeEditorKind.attendance) return false;
    for (var weekday = DateTime.monday;
        weekday <= DateTime.sunday;
        weekday++) {
      final rule = _rules.ruleFor(weekday);
      if (rule.enabled && rule.clockOutMinutes <= rule.clockInMinutes) {
        return true;
      }
    }
    return false;
  }

  Set<int> _targetDays() {
    if (_scope == BulkDateScope.selected) {
      return <int>{..._selectedDays};
    }
    return <int>{
      for (var day = 1; day <= _daysInMonth; day++)
        if (_rules
            .ruleFor(DateTime(widget.month.year, widget.month.month, day).weekday)
            .enabled)
          day,
    };
  }

  BulkTimeApplyResult _generatePreview() {
    return BulkTimeGenerator.generate(
      kind: widget.kind,
      month: widget.month,
      userSeed: widget.userSeed,
      rules: _rules,
      targetDays: _targetDays(),
      currentClockIns: widget.currentClockIns,
      currentClockOuts: widget.currentClockOuts,
      currentBreakTimes: widget.currentBreakTimes,
      loadedClockIns: widget.loadedClockIns,
      loadedClockOuts: widget.loadedClockOuts,
      loadedBreakTimes: widget.loadedBreakTimes,
      pendingDeleteClockInDays: widget.pendingDeleteClockInDays,
      pendingDeleteClockOutDays: widget.pendingDeleteClockOutDays,
      pendingDeleteBreakDays: widget.pendingDeleteBreakDays,
    );
  }

  Future<void> _apply() async {
    if (_applying || _hasInvalidAttendanceRule()) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    if (!enabled) {
      HapticFeedback.mediumImpact();
      widget.onDebugLog('apply_blocked reason=developer_mode_off');
      widget.onBack();
      return;
    }
    final result = _generatePreview();
    if (result.generatedFields == 0) {
      HapticFeedback.mediumImpact();
      widget.onDebugLog(
        'apply_skip generated=0 target=${result.targetDates} existing=${result.existingFields} skipped=${result.skippedDates}',
      );
      return;
    }
    setState(() => _applying = true);
    await Future<void>.delayed(
      MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : const Duration(milliseconds: 150),
    );
    if (!mounted) return;
    widget.onDebugLog(
      'apply_start kind=${widget.kind.name} target=${result.targetDates} generated=${result.generatedFields} existing=${result.existingFields} skipped=${result.skippedDates}',
    );
    for (final entry in result.clockIns.entries) {
      widget.onDebugLog('generated clockIn day=${entry.key} value=${entry.value}');
    }
    for (final entry in result.clockOuts.entries) {
      widget.onDebugLog('generated clockOut day=${entry.key} value=${entry.value}');
    }
    for (final entry in result.breakTimes.entries) {
      widget.onDebugLog('generated break day=${entry.key} value=${entry.value}');
    }
    widget.onApply(result);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() => _applying = false);
    }
  }

  void _setScope(BulkDateScope scope) {
    if (_scope == scope) return;
    HapticFeedback.selectionClick();
    setState(() => _scope = scope);
    widget.onDebugLog('scope_change scope=${scope.name}');
  }

  void _toggleSelectedDay(int day) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedDays.add(day)) {
        _selectedDays.remove(day);
      }
    });
    widget.onDebugLog(
      'date_toggle day=$day selected=${_selectedDays.contains(day)} selectedCount=${_selectedDays.length}',
    );
  }

  void _selectWeekdays() {
    setState(() {
      _selectedDays
        ..clear()
        ..addAll(<int>{
          for (var day = 1; day <= _daysInMonth; day++)
            if (DateTime(widget.month.year, widget.month.month, day).weekday <=
                DateTime.friday)
              day,
        });
    });
    HapticFeedback.selectionClick();
    widget.onDebugLog('selection_weekdays count=${_selectedDays.length}');
  }

  void _selectAllDays() {
    setState(() {
      _selectedDays
        ..clear()
        ..addAll(<int>{for (var day = 1; day <= _daysInMonth; day++) day});
    });
    HapticFeedback.selectionClick();
    widget.onDebugLog('selection_all count=${_selectedDays.length}');
  }

  void _clearSelectedDays() {
    if (_selectedDays.isEmpty) return;
    setState(_selectedDays.clear);
    HapticFeedback.selectionClick();
    widget.onDebugLog('selection_clear');
  }

  Widget _buildHeader(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: '관리 화면으로 돌아가기',
            onPressed: () {
              HapticFeedback.selectionClick();
              widget.onDebugLog('editor_back');
              widget.onBack();
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '일괄 시간 입력',
                  style: text.titleMedium?.copyWith(
                    color: _tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _tokens.warningContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'DEBUG',
                        style: text.labelSmall?.copyWith(
                          color: _tokens.onWarningContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${widget.month.year}.${widget.month.month.toString().padLeft(2, '0')}',
                      style: text.bodySmall?.copyWith(
                        color: _tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: text.bodyMedium?.copyWith(
                color: _tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildTimeButton({
    required String value,
    required VoidCallback? onPressed,
  }) {
    return AnimatedOpacity(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.press,
      opacity: onPressed == null ? 0.48 : 1,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: _tokens.borderSubtle),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
          ),
        ),
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildWeekdayRuleRow(int weekday) {
    final text = Theme.of(context).textTheme;
    final rule = _rules.ruleFor(weekday);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final invalid = widget.kind == BulkTimeEditorKind.attendance &&
        rule.enabled &&
        rule.clockOutMinutes <= rule.clockInMinutes;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      padding: const EdgeInsets.fromLTRB(8, 7, 7, 7),
      decoration: BoxDecoration(
        color: rule.enabled
            ? _tokens.surfaceSelected.withOpacity(.42)
            : _tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(
          color: invalid ? _tokens.danger : _tokens.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              _weekdayLabel(weekday),
              style: text.bodyMedium?.copyWith(
                color: rule.enabled
                    ? _tokens.textPrimary
                    : _tokens.textSecondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Switch.adaptive(
            value: rule.enabled,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (enabled) {
              HapticFeedback.selectionClick();
              _updateRule(weekday, rule.copyWith(enabled: enabled));
            },
          ),
          const SizedBox(width: 4),
          if (widget.kind == BulkTimeEditorKind.attendance) ...[
            Expanded(
              child: _buildTimeButton(
                value: _formatMinutes(rule.clockInMinutes),
                onPressed: rule.enabled
                    ? () async {
                        final value = await _pickMinutes(rule.clockInMinutes);
                        if (value == null) return;
                        _updateRule(
                          weekday,
                          rule.copyWith(clockInMinutes: value),
                        );
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: _tokens.iconSecondary,
              ),
            ),
            Expanded(
              child: _buildTimeButton(
                value: _formatMinutes(rule.clockOutMinutes),
                onPressed: rule.enabled
                    ? () async {
                        final value = await _pickMinutes(rule.clockOutMinutes);
                        if (value == null) return;
                        _updateRule(
                          weekday,
                          rule.copyWith(clockOutMinutes: value),
                        );
                      }
                    : null,
              ),
            ),
          ] else
            Expanded(
              child: _buildTimeButton(
                value: _formatMinutes(rule.breakMinutes),
                onPressed: rule.enabled
                    ? () async {
                        final value = await _pickMinutes(rule.breakMinutes);
                        if (value == null) return;
                        _updateRule(
                          weekday,
                          rule.copyWith(breakMinutes: value),
                        );
                      }
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRulesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          '요일별 기준 시간',
          trailing: TextButton(
            onPressed: _syncWeekdaysFromMonday,
            child: const Text('월~금 동기화'),
          ),
        ),
        for (var weekday = DateTime.monday;
            weekday <= DateTime.sunday;
            weekday++)
          CommonAnimatedReveal(
            delay: Duration(milliseconds: (weekday - 1) * 18),
            offset: const Offset(-0.018, 0),
            child: _buildWeekdayRuleRow(weekday),
          ),
        if (_hasInvalidAttendanceRule())
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: _tokens.danger,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '활성화된 요일의 퇴근 시간은 출근 시간보다 늦어야 합니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _tokens.danger,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildScopeButton(BulkDateScope scope, String label) {
    final selected = _scope == scope;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        onTap: () => _setScope(scope),
        child: AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _tokens.accentContainer : _tokens.surface,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(
              color: selected ? _tokens.accent : _tokens.borderSubtle,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: selected
                      ? _tokens.onAccentContainer
                      : _tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCalendar() {
    final firstDay = DateTime(widget.month.year, widget.month.month, 1);
    final lastDay = DateTime(widget.month.year, widget.month.month, _daysInMonth);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
          child: Row(
            children: [
              TextButton(
                onPressed: _selectWeekdays,
                child: const Text('평일'),
              ),
              TextButton(
                onPressed: _selectAllDays,
                child: const Text('전체'),
              ),
              TextButton(
                onPressed: _selectedDays.isEmpty ? null : _clearSelectedDays,
                child: const Text('해제'),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : CommonUiMotion.selection,
                child: Text(
                  '${_selectedDays.length}일 선택',
                  key: ValueKey<int>(_selectedDays.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _selectedDays.isEmpty
                            ? _tokens.textSecondary
                            : _tokens.accent,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
        ),
        TableCalendar(
          firstDay: firstDay,
          lastDay: lastDay,
          focusedDay: firstDay,
          headerVisible: false,
          rowHeight: 42,
          daysOfWeekHeight: 24,
          availableGestures: AvailableGestures.none,
          selectedDayPredicate: (date) => _selectedDays.contains(date.day),
          onDaySelected: (selectedDay, focusedDay) {
            _toggleSelectedDay(selectedDay.day);
          },
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            isTodayHighlighted: true,
            selectedDecoration: BoxDecoration(
              color: _tokens.accent,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
              color: _tokens.onAccent,
              fontWeight: FontWeight.w800,
            ),
            todayDecoration: BoxDecoration(
              color: _tokens.accentContainer,
              shape: BoxShape.circle,
            ),
            todayTextStyle: TextStyle(
              color: _tokens.onAccentContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: TextStyle(
              color: _tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            weekendStyle: TextStyle(
              color: _tokens.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScopeSection() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle(
          '적용 범위',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _tokens.infoContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '±10분',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _tokens.onInfoContainer,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              _buildScopeButton(BulkDateScope.month, '현재 월'),
              const SizedBox(width: 6),
              _buildScopeButton(BulkDateScope.selected, '날짜 선택'),
            ],
          ),
        ),
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
          curve: CommonUiMotion.standard,
          alignment: Alignment.topCenter,
          child: _scope == BulkDateScope.selected
              ? _buildSelectionCalendar()
              : const SizedBox(height: 8),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, {Color? valueColor}) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(
                color: _tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: text.bodySmall?.copyWith(
              color: valueColor ?? _tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(BulkTimeApplyResult preview) {
    final samples = <String>[];
    if (widget.kind == BulkTimeEditorKind.attendance) {
      final days = <int>{...preview.clockIns.keys, ...preview.clockOuts.keys}.toList()
        ..sort();
      for (final day in days.take(4)) {
        final clockIn = preview.clockIns[day] ?? '—';
        final clockOut = preview.clockOuts[day] ?? '—';
        samples.add('${day.toString().padLeft(2, '0')}일  $clockIn → $clockOut');
      }
    } else {
      final days = preview.breakTimes.keys.toList()..sort();
      for (final day in days.take(4)) {
        samples.add(
          '${day.toString().padLeft(2, '0')}일  ${preview.breakTimes[day]}',
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 12),
      child: AnimatedContainer(
        duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
            ? Duration.zero
            : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(color: _tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '적용 미리보기',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 7),
            _metric('대상 날짜', '${preview.targetDates}일'),
            if (widget.kind == BulkTimeEditorKind.attendance) ...[
              _metric(
                '출근 생성',
                '${preview.clockIns.length}건',
                valueColor: _tokens.accent,
              ),
              _metric(
                '퇴근 생성',
                '${preview.clockOuts.length}건',
                valueColor: _tokens.accent,
              ),
            ] else
              _metric(
                '휴게 생성',
                '${preview.breakTimes.length}건',
                valueColor: _tokens.accent,
              ),
            _metric('기존 필드 유지', '${preview.existingFields}건'),
            if (preview.skippedDates > 0)
              _metric('적용 제외', '${preview.skippedDates}일'),
            if (samples.isNotEmpty) ...[
              const SizedBox(height: 7),
              Divider(height: 1, color: _tokens.borderSubtle),
              const SizedBox(height: 7),
              for (final sample in samples)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    sample,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BulkTimeApplyResult preview) {
    final invalid = _hasInvalidAttendanceRule();
    final canApply = !invalid && preview.generatedFields > 0 && !_applying;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Text(
                invalid
                    ? '시간 규칙 확인 필요'
                    : preview.generatedFields == 0
                        ? '생성 가능한 빈 기록 없음'
                        : '생성 ${preview.generatedFields}건',
                key: ValueKey<String>(
                  '$invalid-${preview.generatedFields}-${preview.targetDates}',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: invalid
                          ? _tokens.danger
                          : preview.generatedFields == 0
                              ? _tokens.textSecondary
                              : _tokens.accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: canApply ? _apply : null,
            icon: _applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('편집값에 적용'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _generatePreview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        Divider(height: 1, color: _tokens.borderSubtle),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  offset: const Offset(-0.02, 0),
                  child: _buildRulesSection(),
                ),
              ),
              SliverToBoxAdapter(
                child: Divider(height: 1, color: _tokens.borderSubtle),
              ),
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 50),
                  offset: const Offset(-0.02, 0),
                  child: _buildScopeSection(),
                ),
              ),
              SliverToBoxAdapter(
                child: CommonAnimatedReveal(
                  delay: const Duration(milliseconds: 85),
                  offset: const Offset(0, 0.02),
                  child: _buildPreviewSection(preview),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: _tokens.borderSubtle),
        CommonAnimatedReveal(
          delay: const Duration(milliseconds: 100),
          offset: const Offset(0, 0.02),
          child: _buildFooter(preview),
        ),
      ],
    );
  }
}
