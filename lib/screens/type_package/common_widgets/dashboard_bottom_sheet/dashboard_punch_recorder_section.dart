import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../utils/app_exit_flag.dart';
import '../../../simple_package/utils/dialog/simple_duration_blocking_dialog.dart';
import '../../../simple_package/utils/simple_mode/simple_mode_attendance_repository.dart';
import 'dashboard_punch_card_feedback.dart';

import '../../../../../repositories/commute_true_false_repository.dart';

/// Teal Palette (Dashboard 전용)
class _Palette {
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// 약식 모드용 출퇴근 기록기 카드
/// - 출근/휴게/퇴근 3개 펀칭
/// - 로컬 SQLite 기록
/// - 추가 정책:
///   - 출근(workIn) 시에만 commute_true_false 에 "출근 시각(Timestamp)" 기록
///   - 퇴근(workOut) 시 commute_true_false 는 무관 (절대 호출하지 않음)
class DashboardInsidePunchRecorderSection extends StatefulWidget {
  const DashboardInsidePunchRecorderSection({
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
  State<DashboardInsidePunchRecorderSection> createState() =>
      _DashboardInsidePunchRecorderSectionState();
}

class _DashboardInsidePunchRecorderSectionState
    extends State<DashboardInsidePunchRecorderSection> {
  late DateTime _selectedDate;

  String? _workInTime;
  String? _breakTime;
  String? _workOutTime;
  bool _loading = true;

  final CommuteTrueFalseRepository _commuteTrueFalseRepo =
  CommuteTrueFalseRepository();

  bool get _hasWorkIn => _workInTime != null && _workInTime!.isNotEmpty;
  bool get _hasBreak => _breakTime != null && _breakTime!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadForDate(_selectedDate);
  }

  Future<void> _loadForDate(DateTime date) async {
    setState(() {
      _loading = true;
    });

    final events =
    await SimpleModeAttendanceRepository.instance.getEventsForDate(date);

    setState(() {
      _selectedDate = date;
      _workInTime = events[SimpleModeAttendanceType.workIn];
      _breakTime = events[SimpleModeAttendanceType.breakTime];
      _workOutTime = events[SimpleModeAttendanceType.workOut];
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final init = _selectedDate;
    final first = DateTime(init.year - 1, 1, 1);
    final last = DateTime(init.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );

    if (picked == null) return;
    await _loadForDate(picked);
  }

  void _showGuardSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// ✅ 출근(workIn) 시에만 commute_true_false에 출근시각 기록
  Future<void> _recordClockInAtToCommuteTrueFalse(DateTime clockInAt) async {
    final company = widget.division.trim();
    final area = widget.area.trim();
    final workerName = widget.userName.trim();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      debugPrint(
        '[DashboardInsidePunchRecorder] commute_true_false(clockInAt) 업데이트 스킵 '
            '(company="$company", area="$area", workerName="$workerName")',
      );
      return;
    }

    await _commuteTrueFalseRepo.setClockInAt(
      company: company,
      area: area,
      workerName: workerName,
      clockInAt: clockInAt,
    );
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    AppExitFlag.beginExit();

    try {
      if (Platform.isAndroid) {
        bool running = false;

        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {
          running = false;
        }

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 서비스 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('포그라운드 서비스 중지 실패: $e')),
              );
            }
          }

          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      await SystemNavigator.pop();
    } catch (e) {
      AppExitFlag.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앱 종료 실패: $e')),
        );
      }
    }
  }

  Future<void> _punch(SimpleModeAttendanceType type) async {
    if (_loading) return;

    if (type == SimpleModeAttendanceType.breakTime && !_hasWorkIn) {
      _showGuardSnack('먼저 출근을 펀칭한 뒤 휴게시간을 펀칭할 수 있습니다.');
      return;
    }

    if (type == SimpleModeAttendanceType.workOut && (!_hasWorkIn || !_hasBreak)) {
      _showGuardSnack('출근과 휴게시간을 모두 펀칭한 뒤 퇴근을 펀칭할 수 있습니다.');
      return;
    }

    if (type == SimpleModeAttendanceType.workIn ||
        type == SimpleModeAttendanceType.workOut) {
      final isClockIn = type == SimpleModeAttendanceType.workIn;

      final proceed = await showSimpleDurationBlockingDialog(
        context,
        message: isClockIn
            ? '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.'
            : '퇴근을 펀칭하면 오늘 근무가 종료되고 앱이 종료됩니다.\n약 5초 정도 소요됩니다.',
        duration: const Duration(seconds: 5),
      );

      if (!proceed) return;
    }

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

    await SimpleModeAttendanceRepository.instance.insertEvent(
      dateTime: targetDateTime,
      type: type,
    );

    await showDashboardPunchCardFeedback(
      context,
      type: type,
      dateTime: targetDateTime,
    );

    // ✅ 출근(workIn)일 때만 Timestamp 기록
    if (type == SimpleModeAttendanceType.workIn) {
      await _recordClockInAtToCommuteTrueFalse(targetDateTime);
    }

    await _loadForDate(_selectedDate);

    if (type == SimpleModeAttendanceType.workOut) {
      await _exitAppAfterClockOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthStr = DateFormat('yyyy.MM').format(_selectedDate);
    final dateStr = DateFormat('MM.dd').format(_selectedDate);
    final textTheme = Theme.of(context).textTheme;

    final bool canPunchWorkIn = true;
    final bool canPunchBreak = _hasWorkIn;
    final bool canPunchWorkOut = _hasWorkIn && _hasBreak;

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _Palette.light.withOpacity(.45)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: _Palette.dark.withOpacity(.8),
                ),
                const SizedBox(width: 4),
                Text(
                  '출퇴근 기록기',
                  style: TextStyle(
                    fontSize: 14,
                    color: _Palette.dark.withOpacity(.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _pickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: _Palette.dark.withOpacity(.8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$monthStr · $dateStr',
                          style: TextStyle(
                            fontSize: 12,
                            color: _Palette.dark.withOpacity(.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '선택한 날짜($dateStr) 기준으로 출근 · 휴게 · 퇴근을 순서대로 펀칭하세요.',
              style: TextStyle(
                fontSize: 11,
                color: _Palette.dark.withOpacity(.6),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FBFA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _Palette.light.withOpacity(.6),
                        width: 0.8,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PunchSlot(
                            label: '출근',
                            type: SimpleModeAttendanceType.workIn,
                            time: _workInTime,
                            enabled: canPunchWorkIn,
                            onTap: () => _punch(SimpleModeAttendanceType.workIn),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '휴게',
                            type: SimpleModeAttendanceType.breakTime,
                            time: _breakTime,
                            enabled: canPunchBreak,
                            onTap: () =>
                                _punch(SimpleModeAttendanceType.breakTime),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '퇴근',
                            type: SimpleModeAttendanceType.workOut,
                            time: _workOutTime,
                            enabled: canPunchWorkOut,
                            onTap: () => _punch(SimpleModeAttendanceType.workOut),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '날짜를 선택해 과거 기록도 수정/재펀칭할 수 있습니다.',
                      style: textTheme.labelSmall?.copyWith(
                        color: _Palette.dark.withOpacity(.55),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PunchSlot extends StatelessWidget {
  final String label;
  final SimpleModeAttendanceType type;
  final String? time;
  final bool enabled;
  final VoidCallback onTap;

  const _PunchSlot({
    required this.label,
    required this.type,
    required this.time,
    required this.enabled,
    required this.onTap,
  });

  Color get _accent {
    switch (type) {
      case SimpleModeAttendanceType.workIn:
        return const Color(0xFF09367D);
      case SimpleModeAttendanceType.breakTime:
        return const Color(0xFFF2A93B);
      case SimpleModeAttendanceType.workOut:
        return const Color(0xFFEF6C53);
    }
  }

  IconData get _icon {
    switch (type) {
      case SimpleModeAttendanceType.workIn:
        return Icons.login;
      case SimpleModeAttendanceType.breakTime:
        return Icons.free_breakfast;
      case SimpleModeAttendanceType.workOut:
        return Icons.logout;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bool punched = time != null && time!.isNotEmpty;

    final borderColor = punched
        ? _accent.withOpacity(0.9)
        : _Palette.light.withOpacity(enabled ? .7 : .35);

    final bgColor = punched ? _accent.withOpacity(0.07) : Colors.white;

    final content = Ink(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: borderColor,
          width: punched ? 1.1 : 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _icon,
                size: 14,
                color: enabled
                    ? _accent.withOpacity(0.9)
                    : _Palette.dark.withOpacity(0.3),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled
                      ? _accent.withOpacity(0.9)
                      : _Palette.dark.withOpacity(0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Icon(
            punched ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: punched
                ? _accent.withOpacity(0.95)
                : _Palette.light.withOpacity(enabled ? .9 : .4),
          ),
          const SizedBox(height: 2),
          Text(
            punched ? '펀칭 완료' : '미펀칭',
            style: textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: punched ? const Color(0xFF2E2720) : const Color(0xFF8C8680),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: content,
      ),
    );
  }
}
