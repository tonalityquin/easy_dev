import 'package:flutter/material.dart';

import '../common/ops_dashboard_side_dock.dart';
import '../../sheets/minor/widgets/minor_dashboard_punch_recorder_section.dart';

class MinorHomeDashboardSideDock extends StatelessWidget {
  const MinorHomeDashboardSideDock({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardSideDock(
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
