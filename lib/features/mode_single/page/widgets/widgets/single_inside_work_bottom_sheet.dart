import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../sheets/report/widgets/single_inside_start_report_form_page.dart';

Future<void> showSingleInsideWorkSideDock(BuildContext context) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[SingleStartReportDock] route_push reduceMotion=$reduceMotion motion=operations_210_190',
  );
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '업무 시작 보고',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: false,
    builder: (_) => const SingleInsideStartReportFormPage(),
  );
  debugPrint('[SingleStartReportDock] route_closed');
}
