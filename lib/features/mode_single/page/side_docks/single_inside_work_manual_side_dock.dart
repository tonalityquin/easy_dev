import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../rule/widgets/work_rule_report_surface.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideWorkManualSideDock extends StatelessWidget {
  const SingleInsideWorkManualSideDock({
    super.key,
    required this.division,
    required this.area,
    required this.capabilityEnabled,
    required this.refreshRevision,
    required this.onClose,
    required this.onDeveloperStatus,
  });

  final String division;
  final String area;
  final bool capabilityEnabled;
  final int refreshRevision;
  final VoidCallback onClose;
  final Future<void> Function() onDeveloperStatus;

  @override
  Widget build(BuildContext context) {
    final areaLabel = area.trim().isEmpty ? '현재 근무지' : area.trim();
    return CommonSideDockFrame(
      title: '업무 메뉴얼',
      subtitle: areaLabel,
      icon: Icons.menu_book_rounded,
      showCloseTooltip: false,
      onClose: onClose,
      onLongPress: () {
        SingleInsideDiagnostics.log(
          'status',
          'developer_status_request source=work_manual_side_dock_header',
        );
        unawaited(onDeveloperStatus());
      },
      child: WorkRuleReportWorkspace(
        division: division,
        area: area,
        capabilityEnabled: capabilityEnabled,
        source: 'single_inside_work_manual_side_dock',
        side: WorkRuleReportSide.right,
        contentMode: WorkRuleReportContentMode.responseManual,
        refreshRevision: refreshRevision,
        showHeader: false,
        onBack: onClose,
        onDebug: (message) => SingleInsideDiagnostics.log(
          'work_manual_dock',
          message,
        ),
      ),
    );
  }
}
