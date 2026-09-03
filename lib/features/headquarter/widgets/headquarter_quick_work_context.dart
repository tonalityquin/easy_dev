import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/app_exit_service.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../attendance/widgets/common_attendance_punch_feedback.dart';
import '../../commute/widgets/common_punch_recorder_surface.dart';
import '../../dashboard/widgets/widgets/schedule/weekly_work_schedule_editor.dart';
import '../../mode_single/application/att_brk_repository.dart';
import '../application/actions/headquarter_common_actions.dart';

class HeadquarterQuickWorkContext extends StatefulWidget {
  const HeadquarterQuickWorkContext({
    super.key,
    required this.developerMode,
    required this.onDeveloperStatus,
    required this.onDebug,
  });

  final bool developerMode;
  final Future<void> Function() onDeveloperStatus;
  final ValueChanged<String> onDebug;

  @override
  State<HeadquarterQuickWorkContext> createState() =>
      _HeadquarterQuickWorkContextState();
}

class _HeadquarterQuickWorkContextState
    extends State<HeadquarterQuickWorkContext> with WidgetsBindingObserver {
  DateTime _selectedDate = DateTime.now();
  String? _workInTime;
  String? _breakTime;
  String? _workOutTime;
  bool _requiresBreak = true;
  bool _loading = true;
  AttBrkModeType? _submitting;

  bool get _hasWorkIn => (_workInTime ?? '').trim().isNotEmpty;
  bool get _hasBreak => (_breakTime ?? '').trim().isNotEmpty;
  bool get _hasWorkOut => (_workOutTime ?? '').trim().isNotEmpty;

  bool get _isSelectedToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(reason: 'init');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(reason: 'resume');
    }
  }

  void _debug(String message) {
    widget.onDebug('work_context $message');
  }

  String _dateKey(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  Future<void> _load({required String reason}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final events =
          await AttBrkRepository.instance.getEventsForDate(_selectedDate);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final requiresBreak = WorkSchedulePrefs.requiresBreakOnDateFromPrefs(
        prefs,
        _selectedDate,
        defaultWhenUnset: true,
      );
      if (!mounted) return;
      setState(() {
        _workInTime = events[AttBrkModeType.workIn];
        _breakTime = events[AttBrkModeType.breakTime];
        _workOutTime = events[AttBrkModeType.workOut];
        _requiresBreak = requiresBreak;
        _loading = false;
      });
      _debug(
        'load_complete reason=$reason date=${_dateKey(_selectedDate)} workIn=${_workInTime ?? ''} break=${_breakTime ?? ''} workOut=${_workOutTime ?? ''} requiresBreak=$_requiresBreak',
      );
    } catch (error, stackTrace) {
      if (mounted) setState(() => _loading = false);
      _debug('load_failure reason=$reason error=$error stack=$stackTrace');
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1, 1, 1);
    final last = DateTime(now.year, now.month, now.day);
    final initial = _selectedDate.isAfter(last) ? last : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
    _debug('date_selected value=${_dateKey(picked)}');
    await _load(reason: 'date_selected');
  }

  Future<void> _showPunchFeedback(
    AttBrkModeType type,
    DateTime recordedAt,
  ) async {
    if (!mounted) return;
    await showCommonAttendancePunchFeedback(
      context,
      type: type,
      dateTime: recordedAt,
      requiresBreak: _requiresBreak,
    );
  }

  Future<void> _recordBreak() async {
    if (!_isSelectedToday ||
        _submitting != null ||
        !_hasWorkIn ||
        _hasWorkOut ||
        !_requiresBreak) {
      _debug(
        'break_blocked selectedToday=$_isSelectedToday submitting=${_submitting?.code ?? ''} hasWorkIn=$_hasWorkIn hasWorkOut=$_hasWorkOut requiresBreak=$_requiresBreak',
      );
      return;
    }
    setState(() => _submitting = AttBrkModeType.breakTime);
    _debug('break_start context=headquarter');
    try {
      await HeadquarterCommonActions.recordBreak(
        context,
        source: 'quick_dock_work_context',
        onRecorded: (recordedAt) => _showPunchFeedback(
          AttBrkModeType.breakTime,
          recordedAt,
        ),
      );
      if (!mounted) return;
      await _load(reason: 'break_complete');
      _debug('break_complete context=headquarter recorded=${_breakTime ?? ''}');
    } catch (error, stackTrace) {
      _debug('break_failure context=headquarter error=$error stack=$stackTrace');
      rethrow;
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  Future<void> _clockOut() async {
    final blocked = !_isSelectedToday ||
        _submitting != null ||
        !_hasWorkIn ||
        (_requiresBreak && !_hasBreak);
    if (blocked) {
      _debug(
        'clock_out_blocked selectedToday=$_isSelectedToday submitting=${_submitting?.code ?? ''} hasWorkIn=$_hasWorkIn hasBreak=$_hasBreak hasWorkOut=$_hasWorkOut requiresBreak=$_requiresBreak',
      );
      return;
    }

    final isRepunch = _hasWorkOut;
    final previousWorkOut = (_workOutTime ?? '').trim();

    setState(() => _submitting = AttBrkModeType.workOut);
    _debug(
      'clock_out_start context=headquarter operation=${isRepunch ? 'repunch' : 'initial'} previous=$previousWorkOut',
    );

    try {
      if (isRepunch) {
        await _repunchClockOut(previousWorkOut: previousWorkOut);
        return;
      }

      await HeadquarterCommonActions.clockOut(
        context,
        source: 'quick_dock_work_context',
        onRecorded: (recordedAt) => _showPunchFeedback(
          AttBrkModeType.workOut,
          recordedAt,
        ),
      );
      if (!mounted) return;
      await _load(reason: 'clock_out_complete');
      _debug(
        'clock_out_complete context=headquarter operation=initial recorded=${_workOutTime ?? ''}',
      );
    } catch (error, stackTrace) {
      _debug(
        'clock_out_failure context=headquarter operation=${isRepunch ? 'repunch' : 'initial'} error=$error stack=$stackTrace',
      );
      rethrow;
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  Future<void> _repunchClockOut({
    required String previousWorkOut,
  }) async {
    final recordedAt = DateTime.now();
    _debug(
      'clock_out_repunch_write_start context=headquarter date=${_dateKey(recordedAt)} previous=$previousWorkOut target=${DateFormat('HH:mm').format(recordedAt)} at=${recordedAt.toIso8601String()}',
    );

    final result = await CommonAttendanceService.replaceClockOut(
      context,
      source: 'headquarter_quick_work_context_repunch',
      isHeadquarter: true,
      recordedAt: recordedAt,
    );
    if (!result.success) {
      throw StateError(result.message);
    }

    _debug(
      'clock_out_repunch_write_complete context=headquarter previous=$previousWorkOut target=${DateFormat('HH:mm').format(recordedAt)} storage=common_attendance_local_replace',
    );

    if (!mounted) return;
    await _showPunchFeedback(
      AttBrkModeType.workOut,
      recordedAt,
    );

    if (!mounted) return;
    await _load(reason: 'clock_out_repunch_complete');
    _debug(
      'clock_out_repunch_complete context=headquarter previous=$previousWorkOut current=${_workOutTime ?? ''}',
    );

    if (!mounted) return;
    if (widget.developerMode) {
      _debug(
        'clock_out_repunch_developer_status context=headquarter date=${_dateKey(_selectedDate)} workIn=${_workInTime ?? ''} break=${_breakTime ?? ''} workOut=${_workOutTime ?? ''} requiresBreak=$_requiresBreak',
      );
      await widget.onDeveloperStatus();
    }

    if (!mounted) return;
    _debug('clock_out_repunch_exit context=headquarter');
    await AppExitService.exitApp(context, useCommonUi: true);
  }

  Future<void> _requestDeveloperStatus() async {
    if (!widget.developerMode || !mounted) return;
    _debug(
      'developer_status_request date=${_dateKey(_selectedDate)} selectedToday=$_isSelectedToday workIn=${_workInTime ?? ''} break=${_breakTime ?? ''} workOut=${_workOutTime ?? ''} hasWorkIn=$_hasWorkIn hasBreak=$_hasBreak hasWorkOut=$_hasWorkOut requiresBreak=$_requiresBreak loading=$_loading submitting=${_submitting?.code ?? ''}',
    );
    await widget.onDeveloperStatus();
  }

  CommonPunchSlotData _workInSlot() {
    if (_submitting == AttBrkModeType.workIn) {
      return const CommonPunchSlotData(
        label: '출근',
        icon: Icons.login,
        tone: CommonPunchTone.info,
        state: CommonPunchSlotState.loading,
        statusLabel: '처리 중',
      );
    }
    if (_hasWorkIn) {
      return CommonPunchSlotData(
        label: '출근',
        icon: Icons.login,
        tone: CommonPunchTone.info,
        state: CommonPunchSlotState.readOnly,
        time: _workInTime,
        statusLabel: '펀칭 완료',
      );
    }
    return const CommonPunchSlotData(
      label: '출근',
      icon: Icons.login,
      tone: CommonPunchTone.info,
      state: CommonPunchSlotState.disabled,
      statusLabel: '미펀칭',
    );
  }

  CommonPunchSlotData _breakSlot() {
    if (_submitting == AttBrkModeType.breakTime) {
      return CommonPunchSlotData(
        label: '휴게',
        icon: Icons.free_breakfast,
        tone: CommonPunchTone.warning,
        state: CommonPunchSlotState.loading,
        time: _breakTime,
        statusLabel: '처리 중',
      );
    }
    if (_hasBreak) {
      return CommonPunchSlotData(
        label: '휴게',
        icon: Icons.free_breakfast,
        tone: CommonPunchTone.warning,
        state: _isSelectedToday && !_hasWorkOut
            ? CommonPunchSlotState.completedActionable
            : CommonPunchSlotState.readOnly,
        time: _breakTime,
        statusLabel: '펀칭 완료',
        onTap: _isSelectedToday && !_hasWorkOut ? _recordBreak : null,
      );
    }
    if (!_isSelectedToday || !_requiresBreak || !_hasWorkIn || _hasWorkOut) {
      return const CommonPunchSlotData(
        label: '휴게',
        icon: Icons.free_breakfast,
        tone: CommonPunchTone.warning,
        state: CommonPunchSlotState.disabled,
        statusLabel: '미펀칭',
      );
    }
    return CommonPunchSlotData(
      label: '휴게',
      icon: Icons.free_breakfast,
      tone: CommonPunchTone.warning,
      state: CommonPunchSlotState.actionable,
      statusLabel: '미펀칭',
      onTap: _recordBreak,
    );
  }

  CommonPunchSlotData _workOutSlot() {
    if (_submitting == AttBrkModeType.workOut) {
      return CommonPunchSlotData(
        label: '퇴근',
        icon: Icons.logout,
        tone: CommonPunchTone.danger,
        state: CommonPunchSlotState.loading,
        time: _workOutTime,
        statusLabel: '처리 중',
      );
    }
    if (!_isSelectedToday ||
        !_hasWorkIn ||
        (_requiresBreak && !_hasBreak)) {
      return const CommonPunchSlotData(
        label: '퇴근',
        icon: Icons.logout,
        tone: CommonPunchTone.danger,
        state: CommonPunchSlotState.disabled,
        statusLabel: '미펀칭',
      );
    }
    return CommonPunchSlotData(
      label: '퇴근',
      icon: Icons.logout,
      tone: CommonPunchTone.danger,
      state: _hasWorkOut
          ? CommonPunchSlotState.completedActionable
          : CommonPunchSlotState.actionable,
      time: _workOutTime,
      statusLabel: _hasWorkOut ? '펀칭 완료' : '미펀칭',
      onTap: _clockOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${DateFormat('yyyy.MM').format(_selectedDate)} · ${DateFormat('MM.dd').format(_selectedDate)}';

    return Semantics(
      container: true,
      label: '나의 근무',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WorkSurfaceReveal(
            order: 0,
            child: WeeklyWorkScheduleEditor(
              source: 'hq_quick_dock',
              onChanged: () => _load(reason: 'schedule_changed'),
            ),
          ),
          const SizedBox(height: 14),
          _WorkSurfaceReveal(
            order: 1,
            child: _WorkInteractionMotion(
              active: _loading || _submitting != null,
              child: CommonPunchRecorderSurface(
                dateLabel: dateLabel,
                onDateTap: _pickDate,
                loading: _loading,
                onDeveloperStatus:
                    widget.developerMode ? _requestDeveloperStatus : null,
                slots: <CommonPunchSlotData>[
                  _workInSlot(),
                  _breakSlot(),
                  _workOutSlot(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkInteractionMotion extends StatelessWidget {
  const _WorkInteractionMotion({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return AnimatedScale(
      scale: active ? 0.992 : 1,
      duration: duration,
      curve: CommonUiMotion.standard,
      child: AnimatedOpacity(
        opacity: active ? 0.965 : 1,
        duration: duration,
        curve: CommonUiMotion.standard,
        child: child,
      ),
    );
  }
}

class _WorkSurfaceReveal extends StatelessWidget {
  const _WorkSurfaceReveal({
    required this.order,
    required this.child,
  });

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final delayMs = math.min(order, 10) * 22;
    const motionMs = 190;
    final totalMs = delayMs + motionMs;
    final start = delayMs / totalMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      child: child,
      builder: (context, value, animatedChild) {
        final normalized = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final motion = Curves.easeOutCubic.transform(normalized);
        return Opacity(
          opacity: motion,
          child: Transform.translate(
            offset: Offset(0, 9 * (1 - motion)),
            child: animatedChild,
          ),
        );
      },
    );
  }
}
