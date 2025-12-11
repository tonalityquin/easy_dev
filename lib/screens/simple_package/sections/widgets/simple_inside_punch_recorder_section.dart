import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../utils/app_exit_flag.dart';
import '../../utils/dialog/simple_duration_blocking_dialog.dart';
import '../../utils/simple_mode/simple_mode_attendance_repository.dart';
import 'simple_punch_card_feedback.dart';

/// Teal Palette (Simple 전용)
class _Palette {
  static const Color dark = Color(0xFF00695C); // 강조 텍스트/아이콘
  static const Color light = Color(0xFF80CBC4); // 톤 변형/보더
}

/// 약식 모드용 출퇴근 기록기 카드
/// - 출근 / 휴게 / 퇴근 3개 펀칭
/// - 기본은 오늘 날짜 기준이지만, 사용자가 날짜를 선택/수정할 수 있음
/// - 헤더에 yyyy.MM · MM.dd 표시 → 날짜를 바꿔 과거 기록 수정 가능
/// - 펀칭 시 **로컬 SQLite에만 기록** (commute_user_logs Firestore는 사용하지 않음)
class SimpleInsidePunchRecorderSection extends StatefulWidget {
  const SimpleInsidePunchRecorderSection({
    super.key,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
  });

  /// (현재는 Firestore를 쓰지 않지만, 메타 정보는 API 호환성을 위해 유지)
  final String userId;
  final String userName;
  final String area;
  final String division;

  @override
  State<SimpleInsidePunchRecorderSection> createState() =>
      _SimpleInsidePunchRecorderSectionState();
}

class _SimpleInsidePunchRecorderSectionState
    extends State<SimpleInsidePunchRecorderSection> {
  // ✅ 선택된 기준 날짜 (기본: 오늘)
  late DateTime _selectedDate;

  String? _workInTime; // 예: 09:01 (DB용, 화면에는 노출하지 않음)
  String? _breakTime;  // 예: 12:30
  String? _workOutTime; // 예: 18:05
  bool _loading = true;

  bool get _hasWorkIn => _workInTime != null && _workInTime!.isNotEmpty;
  bool get _hasBreak => _breakTime != null && _breakTime!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadForDate(_selectedDate);
  }

  /// ✅ 특정 날짜의 출근/휴게/퇴근 기록을 로드 (SQLite)
  Future<void> _loadForDate(DateTime date) async {
    setState(() {
      _loading = true;
    });

    final events =
    await SimpleModeAttendanceRepository.instance.getEventsForDate(date);

    setState(() {
      _selectedDate = date; // 최신 선택 날짜 동기화
      _workInTime = events[SimpleModeAttendanceType.workIn];
      _breakTime = events[SimpleModeAttendanceType.breakTime];
      _workOutTime = events[SimpleModeAttendanceType.workOut];
      _loading = false;
    });
  }

  /// 날짜 선택 다이얼로그
  Future<void> _pickDate() async {
    final init = _selectedDate;
    // 필요에 따라 first/lastDate 범위는 조정 가능
    final first = DateTime(init.year - 1, 1, 1);
    final last = DateTime(init.year + 1, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        // 필요 시 테마 커스터마이징
        return child ?? const SizedBox.shrink();
      },
    );

    if (picked == null) return;

    // 새 날짜 기준으로 DB 조회
    await _loadForDate(picked);
  }

  void _showGuardSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// ✅ 퇴근 후 앱 종료 플로우
  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    // 명시적 종료 플로우 시작 플래그
    AppExitFlag.beginExit();

    try {
      if (Platform.isAndroid) {
        bool running = false;

        // 포그라운드 서비스가 돌아가고 있으면 먼저 중지
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {
          // isRunningService가 예외를 던져도 치명적이진 않으므로 무시
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

          // 서비스 중지 브로드캐스트 약간의 딜레이
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      // 실제 앱 종료
      await SystemNavigator.pop();
    } catch (e) {
      // 종료에 실패하면 플래그 롤백
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

    // ✅ 순서 제약 1: 휴게 펀칭은 출근 후에만 가능
    if (type == SimpleModeAttendanceType.breakTime && !_hasWorkIn) {
      _showGuardSnack('먼저 출근을 펀칭한 뒤 휴게시간을 펀칭할 수 있습니다.');
      return;
    }

    // ✅ 순서 제약 2: 퇴근 펀칭은 출근+휴게 펀칭 후에만 가능
    if (type == SimpleModeAttendanceType.workOut &&
        (!_hasWorkIn || !_hasBreak)) {
      _showGuardSnack('출근과 휴게시간을 모두 펀칭한 뒤 퇴근을 펀칭할 수 있습니다.');
      return;
    }

    // ✅ 출근 / 퇴근 시에는 먼저 duration blocking dialog 실행
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

      // 사용자가 '취소'를 눌렀거나, dialog가 false를 반환하면 즉시 종료
      if (!proceed) {
        return;
      }
    }

    final now = DateTime.now();

    // ✅ "선택한 날짜" + "현재 시각"을 합쳐서 저장
    //
    // - 날짜 부분: _selectedDate (사용자가 고른 날짜)
    // - 시간 부분: 버튼을 실제로 누른 현재 시각(now)
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

    // 1) ✅ SQLite에만 펀칭 기록 저장
    await SimpleModeAttendanceRepository.instance.insertEvent(
      dateTime: targetDateTime,
      type: type,
    );

    // 2) 시각적/촉각 피드백 (출퇴근기록카드 피드백 시트)
    await showSimplePunchCardFeedback(
      context,
      type: type,
      dateTime: targetDateTime,
    );

    // 3) 현재 선택된 날짜의 카드 갱신 (SQLite 재조회)
    await _loadForDate(_selectedDate);

    // 4) 퇴근 펀칭인 경우 앱 종료 플로우 실행
    if (type == SimpleModeAttendanceType.workOut) {
      await _exitAppAfterClockOut(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 화면 표시도 "선택된 날짜" 기준
    final monthStr = DateFormat('yyyy.MM').format(_selectedDate); // 예: 2025.12
    final dateStr = DateFormat('MM.dd').format(_selectedDate); // 예: 12.08

    final textTheme = Theme.of(context).textTheme;

    // 🔒 슬롯별 활성화 여부 계산 (선택된 날짜의 데이터 기준)
    final bool canPunchWorkIn = true; // 출근은 언제든지 가능
    final bool canPunchBreak = _hasWorkIn; // 휴게는 출근 이후 가능
    final bool canPunchWorkOut =
        _hasWorkIn && _hasBreak; // 퇴근은 출근+휴게 이후 가능

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
            // 상단 타이틀 라인
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
                // ✅ 선택 날짜/월 표시 + 날짜 변경 버튼
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
              // ✅ "오늘" → "선택한 날짜"로 문구 변경
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
                            onTap: () =>
                                _punch(SimpleModeAttendanceType.workIn),
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
                            onTap: () =>
                                _punch(SimpleModeAttendanceType.workOut),
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

/// 개별 펀칭 슬롯(출근/휴게/퇴근)
/// - 시간 값은 화면에 표시하지 않고, 펀칭 여부만 시각적으로 표현
/// - enabled=false 이면 반투명 + 탭 비활성화 처리
class _PunchSlot extends StatelessWidget {
  final String label;
  final SimpleModeAttendanceType type;
  final String? time; // null/빈 값 여부만 사용 (펀칭 여부 판단용)
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
        return const Color(0xFF4F9A94); // 출근
      case SimpleModeAttendanceType.breakTime:
        return const Color(0xFFF2A93B); // 휴게
      case SimpleModeAttendanceType.workOut:
        return const Color(0xFFEF6C53); // 퇴근
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
          // 상단: 라벨 + 아이콘
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
          // 하단: 펀칭 여부 시각적 표시 (체크 아이콘 + 텍스트)
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
              color: punched
                  ? const Color(0xFF2E2720)
                  : const Color(0xFF8C8680),
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
