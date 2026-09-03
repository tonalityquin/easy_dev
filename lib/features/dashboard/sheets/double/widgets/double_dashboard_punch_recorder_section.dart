import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../app/init/app_exit_service.dart';
import '../../../../../app/init/work_schedule_prefs.dart';
import '../../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../../features/attendance/application/attendance_diagnostics.dart';
import '../../../../../features/attendance/application/common_attendance_service.dart';
import '../../../../../features/attendance/widgets/common_attendance_punch_feedback.dart';
import '../../../../../features/commute/widgets/common_punch_recorder_surface.dart';
import '../../../../../features/mode_single/application/att_brk_repository.dart';

class DoubleDashboardInsidePunchRecorderSection extends StatefulWidget {
  const DoubleDashboardInsidePunchRecorderSection({
    super.key,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
  });

  final String userId;
  final String userName;
  final String area;
  final String division;

  @override
  State<DoubleDashboardInsidePunchRecorderSection> createState() => _DoubleDashboardInsidePunchRecorderSectionState();
}

class _DoubleDashboardInsidePunchRecorderSectionState extends State<DoubleDashboardInsidePunchRecorderSection> {
  late DateTime _selectedDate;
  String? _workInTime;
  String? _breakTime;
  String? _workOutTime;
  bool _loading = true;
  bool _requiresBreak = true;
  AttBrkModeType? _submitting;

  bool get _hasWorkIn => (_workInTime ?? '').trim().isNotEmpty;
  bool get _hasBreak => (_breakTime ?? '').trim().isNotEmpty;
  bool get _hasWorkOut => (_workOutTime ?? '').trim().isNotEmpty;
  bool get _disableWorkInPunch => true;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadForDate(_selectedDate);
  }

  void _debug(String message) {
    debugPrint('[DoublePunchRecorder] $message');
  }

  Future<void> _loadForDate(DateTime date) async {
    if (mounted) setState(() => _loading = true);
    try {
      final events = await AttBrkRepository.instance.getEventsForDate(date);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final requiresBreak = WorkSchedulePrefs.requiresBreakOnDateFromPrefs(
        prefs,
        date,
        defaultWhenUnset: true,
      );
      if (!mounted) return;
      setState(() {
        _selectedDate = date;
        _workInTime = events[AttBrkModeType.workIn];
        _breakTime = events[AttBrkModeType.breakTime];
        _workOutTime = events[AttBrkModeType.workOut];
        _requiresBreak = requiresBreak;
        _loading = false;
      });
      _debug(
        'load date=${DateFormat('yyyy-MM-dd').format(date)} workIn=${_workInTime ?? ''} break=${_breakTime ?? ''} workOut=${_workOutTime ?? ''} requiresBreak=$_requiresBreak',
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _loading = false);
      _debug('load_failure error=$error stack=$stackTrace');
    }
  }

  Future<void> _pickDate() async {
    final init = _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(init.year - 1, 1, 1),
      lastDate: DateTime(init.year + 1, 12, 31),
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
    if (picked == null) return;
    await _loadForDate(picked);
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    await AppExitService.exitApp(context);
  }

  Future<void> _punch(AttBrkModeType type) async {
    if (_loading || _submitting != null) return;
    if (type == AttBrkModeType.workIn) return;
    if (type == AttBrkModeType.breakTime &&
        (!_requiresBreak || !_hasWorkIn || _hasWorkOut)) {
      return;
    }
    if (type == AttBrkModeType.workOut &&
        (!_hasWorkIn || (_requiresBreak && !_hasBreak))) {
      return;
    }
    setState(() => _submitting = type);
    final now = DateTime.now();
    final targetDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    final repunch = type == AttBrkModeType.workOut &&
        (_workOutTime ?? '').trim().isNotEmpty;
    _debug(
      'punch_start type=${type.code} mode=double repunch=$repunch dateTime=${targetDateTime.toIso8601String()}',
    );
    try {
      final result = type == AttBrkModeType.breakTime
          ? await CommonAttendanceService.recordBreak(
              context,
              source: 'double_punch_recorder',
              modeKey: 'double',
              recordedAt: targetDateTime,
            )
          : repunch
              ? await CommonAttendanceService.replaceClockOut(
                  context,
                  source: 'double_punch_recorder_repunch',
                  modeKey: 'double',
                  recordedAt: targetDateTime,
                )
              : await CommonAttendanceService.clockOut(
                  context,
                  source: 'double_punch_recorder',
                  modeKey: 'double',
                  recordedAt: targetDateTime,
                );
      if (!result.success) {
        throw StateError(result.message);
      }
      if (!mounted) return;
      await showCommonAttendancePunchFeedback(
        context,
        type: type,
        dateTime: targetDateTime,
        requiresBreak: _requiresBreak,
      );
      if (!mounted) return;
      await _loadForDate(_selectedDate);
      _debug('punch_complete type=${type.code} mode=double repunch=$repunch');
      if (type == AttBrkModeType.workOut && mounted) {
        await _exitAppAfterClockOut(context);
      }
    } catch (error, stackTrace) {
      _debug(
        'punch_failure type=${type.code} mode=double repunch=$repunch error=$error stack=$stackTrace',
      );
      rethrow;
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  Future<void> _showDeveloperStatus() async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '출퇴근 기록기 상태',
      initialMessage: '출퇴근 기록기 상태를 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
    );
    trace.log('component=DoublePunchRecorder', progress: .16);
    trace.log(
      'date=${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
      progress: .28,
    );
    trace.log('workIn=${_workInTime ?? ''}', progress: .4);
    trace.log('break=${_breakTime ?? ''}', progress: .52);
    trace.log('workOut=${_workOutTime ?? ''}', progress: .64);
    trace.log('requiresBreak=$_requiresBreak', progress: .72);
    trace.log('hasWorkOut=$_hasWorkOut', progress: .78);
    trace.log('breakPolicy=time_independent', progress: .82);
    trace.log('breakAllowedWithoutScheduledTimes=true', progress: .86);
    trace.log('clockOutRequiresBreakWhenConfigured=true', progress: .9);
    trace.log('workInReadOnly=$_disableWorkInPunch', progress: .94);
    trace.log('submitting=${_submitting?.code ?? ''}', progress: .97);
    for (final line in AttendanceDiagnostics.lines) {
      trace.log(line);
    }
    await trace.succeed('출퇴근 기록기 상태 확인을 완료했습니다.');
  }

  CommonPunchSlotData _workInSlot() {
    if (_submitting == AttBrkModeType.workIn) {
      return CommonPunchSlotData(
        label: '출근',
        icon: Icons.login_rounded,
        tone: CommonPunchTone.info,
        state: CommonPunchSlotState.loading,
        time: _workInTime,
        statusLabel: '처리 중',
      );
    }
    if (_disableWorkInPunch) {
      return CommonPunchSlotData(
        label: '출근',
        icon: Icons.login_rounded,
        tone: CommonPunchTone.info,
        state: _hasWorkIn
            ? CommonPunchSlotState.readOnly
            : CommonPunchSlotState.disabled,
        time: _workInTime,
        statusLabel: _hasWorkIn ? '로그인 기록' : '기록 없음',
      );
    }
    return CommonPunchSlotData(
      label: '출근',
      icon: Icons.login_rounded,
      tone: CommonPunchTone.info,
      state: _hasWorkIn
          ? CommonPunchSlotState.completedActionable
          : CommonPunchSlotState.actionable,
      time: _workInTime,
      statusLabel: _hasWorkIn ? '완료' : '기록',
      onTap: () => _punch(AttBrkModeType.workIn),
    );
  }

  CommonPunchSlotData _breakSlot() {
    if (_submitting == AttBrkModeType.breakTime) {
      return CommonPunchSlotData(
        label: '휴게',
        icon: Icons.coffee_rounded,
        tone: CommonPunchTone.warning,
        state: CommonPunchSlotState.loading,
        time: _breakTime,
        statusLabel: '처리 중',
      );
    }
    if (!_requiresBreak) {
      return const CommonPunchSlotData(
        label: '휴게',
        icon: Icons.coffee_rounded,
        tone: CommonPunchTone.warning,
        state: CommonPunchSlotState.disabled,
        statusLabel: '휴게 없음',
      );
    }
    if (!_hasWorkIn) {
      return const CommonPunchSlotData(
        label: '휴게',
        icon: Icons.coffee_rounded,
        tone: CommonPunchTone.warning,
        state: CommonPunchSlotState.disabled,
        statusLabel: '대기',
      );
    }
    if (_hasWorkOut) {
      return CommonPunchSlotData(
        label: '휴게',
        icon: Icons.coffee_rounded,
        tone: CommonPunchTone.warning,
        state: _hasBreak
            ? CommonPunchSlotState.readOnly
            : CommonPunchSlotState.disabled,
        time: _breakTime,
        statusLabel: _hasBreak ? '완료' : '종료',
      );
    }
    return CommonPunchSlotData(
      label: '휴게',
      icon: Icons.coffee_rounded,
      tone: CommonPunchTone.warning,
      state: _hasBreak
          ? CommonPunchSlotState.completedActionable
          : CommonPunchSlotState.actionable,
      time: _breakTime,
      statusLabel: _hasBreak ? '완료' : '기록',
      onTap: () => _punch(AttBrkModeType.breakTime),
    );
  }

  CommonPunchSlotData _workOutSlot() {
    if (_submitting == AttBrkModeType.workOut) {
      return CommonPunchSlotData(
        label: '퇴근',
        icon: Icons.logout_rounded,
        tone: CommonPunchTone.danger,
        state: CommonPunchSlotState.loading,
        time: _workOutTime,
        statusLabel: '처리 중',
      );
    }
    if (!_hasWorkIn || (_requiresBreak && !_hasBreak)) {
      return const CommonPunchSlotData(
        label: '퇴근',
        icon: Icons.logout_rounded,
        tone: CommonPunchTone.danger,
        state: CommonPunchSlotState.disabled,
        statusLabel: '대기',
      );
    }
    final completed = (_workOutTime ?? '').trim().isNotEmpty;
    return CommonPunchSlotData(
      label: '퇴근',
      icon: Icons.logout_rounded,
      tone: CommonPunchTone.danger,
      state: completed
          ? CommonPunchSlotState.completedActionable
          : CommonPunchSlotState.actionable,
      time: _workOutTime,
      statusLabel: completed ? '완료' : '기록',
      onTap: () => _punch(AttBrkModeType.workOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${DateFormat('yyyy.MM').format(_selectedDate)} · ${DateFormat('MM.dd').format(_selectedDate)}';
    return CommonPunchRecorderSurface(
      dateLabel: dateLabel,
      onDateTap: _pickDate,
      loading: _loading,
      onDeveloperStatus: _showDeveloperStatus,
      slots: <CommonPunchSlotData>[
        _workInSlot(),
        _breakSlot(),
        _workOutSlot(),
      ],
    );
  }
}
