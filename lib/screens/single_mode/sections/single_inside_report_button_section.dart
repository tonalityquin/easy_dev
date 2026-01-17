import 'package:flutter/material.dart';

import 'single_inside_report_selector_sheet.dart';

class SingleInsideReportButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SingleInsideReportButtonSection({
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
      // 🔹 문서철 스타일의 선택 시트 → 선택 결과에 따라 시작/종료 보고서 폼 오픈
      onPressed: isDisabled
          ? null
          : () => openSingleInsideReportSelectorSheet(context),
    );
  }
}
