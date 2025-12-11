// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_button_section.dart
import 'package:flutter/material.dart';

import '../../sections3/widgets/simple_inside_report_bottom_sheet.dart';
class SimpleInsideReportButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SimpleInsideReportButtonSection({
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
      onPressed: isDisabled ? null : () => showSimpleInsideReportFullScreenBottomSheet(context),
    );
  }
}
