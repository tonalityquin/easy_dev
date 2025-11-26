import 'package:flutter/material.dart';

import 'sections/simple_inside_report_form_page.dart';

void showSimpleInsideReportFullScreenBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const FractionallySizedBox(
      heightFactor: 1,
      child: SimpleInsideReportFormPage(),
    ),
  );
}
