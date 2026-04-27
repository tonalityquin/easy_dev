import 'package:flutter/material.dart';

import '../../sheets/report/widgets/single_inside_start_report_form_page.dart';

void showSingleInsideWorkFullScreenBottomSheet(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => const SingleInsideStartReportFormPage(),
      fullscreenDialog: true,
    ),
  );
}
