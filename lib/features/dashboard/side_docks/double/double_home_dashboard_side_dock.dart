import 'package:flutter/material.dart';

import '../common/ops_dashboard_side_dock.dart';
import '../../sheets/double/widgets/double_dashboard_punch_recorder_section.dart';

class DoubleHomeDashboardSideDock extends StatelessWidget {
  const DoubleHomeDashboardSideDock({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardSideDock(
      modeLabel: '경량형',
      modeIcon: Icons.speed_rounded,
      punchRecorderBuilder: (context, userState, areaState) {
        return DoubleDashboardInsidePunchRecorderSection(
          userId: userState.name,
          userName: userState.name,
          area: areaState.currentArea,
          division: areaState.currentDivision,
        );
      },
    );
  }
}
