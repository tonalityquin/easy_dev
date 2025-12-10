import 'package:flutter/material.dart';
import 'package:easydev/time_record/simple_mode/simple_mode_attendance_repository.dart';

import 'widgets/simple_punch_card_feedback.dart';


class SimpleInsideWorkButtonSection extends StatelessWidget {
  /// 필요하다면 보고 버튼처럼 비활성화 플래그도 쓸 수 있게 확장
  final bool isDisabled;

  const SimpleInsideWorkButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(
        Icons.access_time,
      ),
      label: const Text(
        '출근하기',
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

        // 1) SQLite에 출근 기록 저장
        await SimpleModeAttendanceRepository.instance.insertEvent(
          dateTime: now,
          type: SimpleModeAttendanceType.workIn,
        );

        // 2) 타임카드 펀칭 연출
        await showPunchCardFeedback(
          context,
          type: SimpleModeAttendanceType.workIn,
          dateTime: now,
        );
      },
    );
  }
}
