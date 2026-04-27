import 'package:flutter/material.dart';

import '../../sheets/report/widgets/single_inside_end_report_form_page.dart';

void showSingleInsideReportFullScreenBottomSheet(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => const SingleInsideEndReportFormPage(),
      fullscreenDialog: true,
    ),
  );
}
