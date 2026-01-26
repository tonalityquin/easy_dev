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
    final cs = Theme.of(context).colorScheme;

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
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: BorderSide(color: cs.primary, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      onPressed: isDisabled ? null : () => openSingleInsideReportSelectorSheet(context),
    );
  }
}
