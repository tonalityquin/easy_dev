// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_button_section.dart
import 'package:flutter/material.dart';

// 같은 디렉토리에 둘 헬퍼 파일 import
import '../widgets/commute_inside_report_bottom_sheet.dart';

class CommuteInsideReportButtonSection extends StatelessWidget {
  final bool isDisabled;

  const CommuteInsideReportButtonSection({
    super.key,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.report),
      label: const Text(
        '업무 보고',
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
      onPressed: isDisabled ? null : () => showCommuteInsideReportFullScreenBottomSheet(context),
    );
  }
}
