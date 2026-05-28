import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/account/applications/user_state.dart';
import 'work_schedule_prefs.dart';

Future<void> showMissingWeekdayEndTimeDialogIfNeeded(
  BuildContext context, {
  DateTime? clockInAt,
}) async {
  if (!context.mounted) return;

  final userState = context.read<UserState>();
  if (userState.isTablet) return;

  final target = clockInAt ?? DateTime.now();
  final now = DateTime.now();
  if (!_isSameDate(target, now)) return;

  final prefs = await SharedPreferences.getInstance();
  final endByDay = WorkSchedulePrefs.readDayTimeMapFromPrefs(
    prefs,
    WorkSchedulePrefs.endMapKey,
  );
  final day = WorkSchedulePrefs.days[target.weekday - 1];
  if (endByDay[day] != null) return;

  if (!context.mounted) return;

  final picked = await showDialog<TimeOfDay>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _MissingWeekdayEndTimeDialog(day: day);
    },
  );

  if (picked == null) return;
  if (!context.mounted) return;

  final saved = await userState.setCurrentUserWeekdayEndTime(
    day: day,
    endTime: picked,
  );

  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        saved
            ? '$day요일 정규 퇴근 시간이 ${WorkSchedulePrefs.formatTime(picked)}로 저장되었습니다.'
            : '퇴근 시간 저장에 실패했습니다. 사용자 정보를 확인해 주세요.',
      ),
    ),
  );
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MissingWeekdayEndTimeDialog extends StatefulWidget {
  const _MissingWeekdayEndTimeDialog({required this.day});

  final String day;

  @override
  State<_MissingWeekdayEndTimeDialog> createState() =>
      _MissingWeekdayEndTimeDialogState();
}

class _MissingWeekdayEndTimeDialogState
    extends State<_MissingWeekdayEndTimeDialog> {
  TimeOfDay _selected = const TimeOfDay(hour: 18, minute: 0);

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selected,
      helpText: '${widget.day}요일 퇴근 시간',
      confirmText: '선택',
      cancelText: '취소',
    );

    if (picked == null) return;
    setState(() {
      _selected = picked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeText = WorkSchedulePrefs.formatTime(_selected) ?? '18:00';

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: Color(0xFFF97316),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '퇴근 시간 설정이 필요합니다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘은 ${widget.day}요일 기본 퇴근 시간이 설정되어 있지 않습니다. 퇴근 이후 안내를 위해 해당 요일의 정규 퇴근 시간을 설정해 주세요.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '퇴근 예정 시간',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF111827),
                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.access_time_rounded, size: 20),
                    label: Text(
                      timeText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '저장하면 이 요일의 정규 퇴근 시간으로 적용됩니다.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('넘기기'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('저장하기'),
        ),
      ],
    );
  }
}
