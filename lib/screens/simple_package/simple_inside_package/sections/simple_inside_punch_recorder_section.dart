// lib/screens/simple_package/simple_inside_package/sections/simple_inside_punch_recorder_section.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:easydev/time_record/simple_mode/simple_mode_attendance_repository.dart';

import 'widgets/simple_punch_card_feedback.dart';

/// Teal Palette (Simple 전용)
class _Palette {
  static const Color dark = Color(0xFF00695C); // 강조 텍스트/아이콘
  static const Color light = Color(0xFF80CBC4); // 톤 변형/보더
}

/// 약식 모드용 출퇴근 기록기 카드
/// - 출근 / 휴게 / 퇴근 3개 펀칭
/// - 오늘 날짜 기준
/// - 헤더에 yyyy.MM 표시 → 달이 바뀌면 자동으로 새 카드처럼 보임
class SimpleInsidePunchRecorderSection extends StatefulWidget {
  const SimpleInsidePunchRecorderSection({super.key});

  @override
  State<SimpleInsidePunchRecorderSection> createState() => _SimpleInsidePunchRecorderSectionState();
}

class _SimpleInsidePunchRecorderSectionState extends State<SimpleInsidePunchRecorderSection> {
  String? _workInTime; // 예: 09:01 (DB용, 화면에는 노출하지 않음)
  String? _breakTime; // 예: 12:30
  String? _workOutTime; // 예: 18:05
  bool _loading = true;

  bool get _hasWorkIn => _workInTime != null && _workInTime!.isNotEmpty;

  bool get _hasBreak => _breakTime != null && _breakTime!.isNotEmpty;
  
  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final now = DateTime.now();
    final events = await SimpleModeAttendanceRepository.instance.getEventsForDate(now);

    setState(() {
      _workInTime = events[SimpleModeAttendanceType.workIn];
      _breakTime = events[SimpleModeAttendanceType.breakTime];
      _workOutTime = events[SimpleModeAttendanceType.workOut];
      _loading = false;
    });
  }

  void _showGuardSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _punch(SimpleModeAttendanceType type) async {
    if (_loading) return;

    // ✅ 순서 제약 1: 휴게 펀칭은 출근 후에만 가능
    if (type == SimpleModeAttendanceType.breakTime && !_hasWorkIn) {
      _showGuardSnack('먼저 출근을 펀칭한 뒤 휴게시간을 펀칭할 수 있습니다.');
      return;
    }

    // ✅ 순서 제약 2: 퇴근 펀칭은 출근+휴게 펀칭 후에만 가능
    if (type == SimpleModeAttendanceType.workOut && (!_hasWorkIn || !_hasBreak)) {
      _showGuardSnack('출근과 휴게시간을 모두 펀칭한 뒤 퇴근을 펀칭할 수 있습니다.');
      return;
    }

    final now = DateTime.now();

    // 1) DB에 펀칭 기록 저장 (하루에 한 번씩만, 마지막 기록 유지)
    await SimpleModeAttendanceRepository.instance.insertEvent(
      dateTime: now,
      type: type,
    );

    // 2) 시각적/촉각 피드백 (출퇴근기록카드 바텀시트)
    await showPunchCardFeedback(
      context,
      type: type,
      dateTime: now,
    );

    // 3) 오늘 카드 갱신
    await _loadToday();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStr = DateFormat('yyyy.MM').format(now); // 2025.12
    final dateStr = DateFormat('MM.dd').format(now); // 12.08

    final textTheme = Theme.of(context).textTheme;

    // 🔒 슬롯별 활성화 여부 계산
    final bool canPunchWorkIn = true; // 출근은 언제든지 가능
    final bool canPunchBreak = _hasWorkIn; // 휴게는 출근 이후 가능
    final bool canPunchWorkOut = _hasWorkIn && _hasBreak; // 퇴근은 출근+휴게 이후 가능

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
                Text(
                  monthStr,
                  style: TextStyle(
                    fontSize: 12,
                    color: _Palette.dark.withOpacity(.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '오늘(${dateStr}) 출근 · 휴게 · 퇴근을 순서대로 펀칭하세요.',
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
                            onTap: () => _punch(SimpleModeAttendanceType.breakTime),
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
                      '월이 바뀌면 자동으로 새 카드에서 펀칭이 시작됩니다.',
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

    final borderColor = punched ? _accent.withOpacity(0.9) : _Palette.light.withOpacity(enabled ? .7 : .35);

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
                color: enabled ? _accent.withOpacity(0.9) : _Palette.dark.withOpacity(0.3),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled ? _accent.withOpacity(0.9) : _Palette.dark.withOpacity(0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 하단: 펀칭 여부 시각적 표시 (체크 아이콘 + 텍스트)
          Icon(
            punched ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: punched ? _accent.withOpacity(0.95) : _Palette.light.withOpacity(enabled ? .9 : .4),
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
