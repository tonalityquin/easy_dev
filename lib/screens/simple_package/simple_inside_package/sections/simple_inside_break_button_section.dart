// lib/screens/simple_package/simple_inside_package/sections/simple_inside_break_button_section.dart

import 'package:flutter/material.dart';

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
          : () {
        // TODO: 실제 휴게 시간 기능(예: AppRoutes.breakSheet 이동 또는 전용 바텀시트)으로 교체
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('휴게 시간 기능은 아직 연결되지 않았습니다.'),
          ),
        );
      },
    );
  }
}
