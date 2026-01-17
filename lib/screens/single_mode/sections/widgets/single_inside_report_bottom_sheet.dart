import 'package:flutter/material.dart';

import 'report_package/single_inside_end_report_form_page.dart';

void showSingleInsideReportFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SingleInsideEndReportFormPage(),
    ),
  );
}
