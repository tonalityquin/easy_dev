import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../../../utils/app_exit_flag.dart';
import '../../../../../../utils/block_dialogs/work_end_duration_blocking_dialog.dart';
import '../../../../../single_mode/utils/att_brk_repository.dart';
import 'minor_dashboard_punch_card_feedback.dart';

import '../../../../../../repositories/commute_repo_services/commute_true_false_repository.dart';

// ✅ 추가: 기기별 commute_true_false Firestore 업데이트 ON/OFF
import '../../../../../../utils/commute_true_false_mode_config.dart';

/// Teal Palette (Dashboard 전용)
class _Palette {
  static const dark = Color(0xFF37474F);
  static const light = Color(0xFFB0BEC5);
}

/// 약식 모드용 출퇴근 기록기 카드
/// - 출근/휴게/퇴근 3개 펀칭
/// - 로컬 SQLite 기록
/// - 정책(변경):
///   - 서비스 로그인에서 이미 출근을 처리하므로, 이 화면에서는 "출근"은 절대 펀칭하지 않음(버튼 비활성)
///   - 휴게/퇴근만 사용자 조작 가능
/// - 추가 정책:
///   - (기존 코드 유지) 출근(workIn) 시에만 commute_true_false 에 "출근 시각(Timestamp)" 기록
///     단, 이 화면에서 workIn을 막았으므로 이 경로는 사실상 실행되지 않음(안전망으로 로직만 유지)
///   - 퇴근(workOut) 시 commute_true_false 는 무관 (절대 호출하지 않음)
class MinorDashboardPunchRecorderSection extends StatefulWidget {
  const MinorDashboardPunchRecorderSection({
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
  State<MinorDashboardPunchRecorderSection> createState() =>
      _MinorDashboardPunchRecorderSectionState();
}

class _MinorDashboardPunchRecorderSectionState
    extends State<MinorDashboardPunchRecorderSection> {
  late DateTime _selectedDate;

  String? _workInTime;
  String? _breakTime;
  String? _workOutTime;
  bool _loading = true;

  final CommuteTrueFalseRepository _commuteTrueFalseRepo =
  CommuteTrueFalseRepository();

  bool get _hasWorkIn => _workInTime != null && _workInTime!.isNotEmpty;
  bool get _hasBreak => _breakTime != null && _breakTime!.isNotEmpty;

  // ✅ 이 화면에서는 "출근" 펀칭을 허용하지 않음(서비스 로그인에서 이미 출근 처리됨)
  bool get _disableWorkInPunch => true;

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
    await AttBrkRepository.instance.getEventsForDate(date);

    setState(() {
      _selectedDate = date;
      _workInTime = events[AttBrkModeType.workIn];
      _breakTime = events[AttBrkModeType.breakTime];
      _workOutTime = events[AttBrkModeType.workOut];
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
    // ✅ 기기 설정이 OFF면 Firestore 업데이트 스킵 (SQLite는 이미 저장됨)
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      debugPrint(
        '[DashboardInsidePunchRecorder] commute_true_false OFF(기기 설정) → 업데이트 스킵',
      );
      return;
    }

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

  Future<void> _punch(AttBrkModeType type) async {
    if (_loading) return;

    // ✅ 추가 가드: 이 화면에서는 출근 펀칭 금지
    if (type == AttBrkModeType.workIn && _disableWorkInPunch) {
      _showGuardSnack('출근은 서비스 로그인에서 처리됩니다. 이 화면에서는 변경할 수 없습니다.');
      return;
    }

    if (type == AttBrkModeType.breakTime && !_hasWorkIn) {
      _showGuardSnack('먼저 출근을 펀칭한 뒤 휴게시간을 펀칭할 수 있습니다.');
      return;
    }

    if (type == AttBrkModeType.workOut && (!_hasWorkIn || !_hasBreak)) {
      _showGuardSnack('출근과 휴게시간을 모두 펀칭한 뒤 퇴근을 펀칭할 수 있습니다.');
      return;
    }

    if (type == AttBrkModeType.workIn ||
        type == AttBrkModeType.workOut) {
      final isClockIn = type == AttBrkModeType.workIn;

      final proceed = await showWorkEndDurationBlockingDialog(
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

    await AttBrkRepository.instance.insertEvent(
      dateTime: targetDateTime,
      type: type,
    );

    await showMinorDashboardPunchCardFeedback(
      context,
      type: type,
      dateTime: targetDateTime,
    );

    // ✅ 출근(workIn)일 때만 Timestamp 기록(단, 기기 설정 OFF면 내부에서 스킵)
    //    (현재 화면에선 workIn을 막았으므로 사실상 실행되지 않음)
    if (type == AttBrkModeType.workIn) {
      await _recordClockInAtToCommuteTrueFalse(targetDateTime);
    }

    await _loadForDate(_selectedDate);

    if (type == AttBrkModeType.workOut) {
      await _exitAppAfterClockOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthStr = DateFormat('yyyy.MM').format(_selectedDate);
    final dateStr = DateFormat('MM.dd').format(_selectedDate);
    final textTheme = Theme.of(context).textTheme;

    // ✅ 변경: 출근은 이 화면에서 항상 비활성
    final bool canPunchWorkIn = !_disableWorkInPunch ? true : false;

    // 휴게/퇴근은 기존 로직 유지(출근/휴게 기록 유무에 따라 활성)
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
              // ✅ 문구도 정책에 맞게 조정(출근은 여기서 불가)
              '선택한 날짜($dateStr) 기준으로 휴게 · 퇴근을 순서대로 펀칭하세요.\n'
                  '출근은 서비스 로그인에서 처리되며, 이 화면에서는 변경할 수 없습니다.',
              style: TextStyle(
                fontSize: 11,
                color: _Palette.dark.withOpacity(.6),
                height: 1.35,
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
                            type: AttBrkModeType.workIn,
                            time: _workInTime,
                            enabled: canPunchWorkIn, // ✅ 항상 false
                            onTap: () => _punch(AttBrkModeType.workIn),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '휴게',
                            type: AttBrkModeType.breakTime,
                            time: _breakTime,
                            enabled: canPunchBreak,
                            onTap: () =>
                                _punch(AttBrkModeType.breakTime),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _PunchSlot(
                            label: '퇴근',
                            type: AttBrkModeType.workOut,
                            time: _workOutTime,
                            enabled: canPunchWorkOut,
                            onTap: () => _punch(AttBrkModeType.workOut),
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
  final AttBrkModeType type;
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
      case AttBrkModeType.workIn:
        return const Color(0xFF09367D);
      case AttBrkModeType.breakTime:
        return const Color(0xFFF2A93B);
      case AttBrkModeType.workOut:
        return const Color(0xFFEF6C53);
    }
  }

  IconData get _icon {
    switch (type) {
      case AttBrkModeType.workIn:
        return Icons.login;
      case AttBrkModeType.breakTime:
        return Icons.free_breakfast;
      case AttBrkModeType.workOut:
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
