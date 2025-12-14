import 'package:flutter/material.dart';

import 'simple_report_package/simple_inside_start_report_form_page.dart';

void showSimpleInsideWorkFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SimpleInsideStartReportFormPage(),
    ),
  );
}
