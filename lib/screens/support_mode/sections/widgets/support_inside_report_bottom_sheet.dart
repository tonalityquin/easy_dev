import 'package:flutter/material.dart';

import 'report_package/support_inside_end_report_form_page.dart';

void showSupportInsideReportFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SupportInsideEndReportFormPage(),
    ),
  );
}
