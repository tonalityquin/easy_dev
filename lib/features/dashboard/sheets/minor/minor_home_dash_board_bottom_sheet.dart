import 'package:flutter/material.dart';

import '../common/ops_dashboard_bottom_sheet.dart';
import 'widgets/minor_dashboard_punch_recorder_section.dart';

class MinorHomeDashBoardBottomSheet extends StatelessWidget {
  const MinorHomeDashBoardBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardBottomSheet(
      modeLabel: '확장형',
      modeIcon: Icons.account_tree_rounded,
      punchRecorderBuilder: (context, userState, areaState) {
        return MinorDashboardPunchRecorderSection(
          userId: userState.name,
          userName: userState.name,
          area: areaState.currentArea,
          division: areaState.currentDivision,
        );
      },
    );
  }
}
