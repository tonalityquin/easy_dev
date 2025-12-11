import 'package:flutter/material.dart';

import '../../../../time_record/simple_mode/simple_mode_attendance_repository.dart';

/// 팀원 모드용 "휴게 시간" 버튼 섹션
class SimpleInsideBreakButtonSection extends StatelessWidget {
  const SimpleInsideBreakButtonSection({
    super.key,
    this.isDisabled = false,
  });

  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.free_breakfast),
      label: const Text(
        '휴게 시간',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: isDisabled
          ? null
          : () async {
        final now = DateTime.now();

        // ✅ 휴게 시간 버튼 누른 시각을 SQLite에 기록
        await SimpleModeAttendanceRepository.instance.insertEvent(
          dateTime: now,
          type: SimpleModeAttendanceType.breakTime,
        );

        // 간단 피드백
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('휴게 시간이 기록되었습니다.'),
          ),
        );
      },
    );
  }
}
