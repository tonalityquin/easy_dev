import 'package:flutter/material.dart';

import '../common/ops_dashboard_bottom_sheet.dart';
import 'widgets/double_dashboard_punch_recorder_section.dart';

class DoubleHomeDashBoardBottomSheet extends StatelessWidget {
  const DoubleHomeDashBoardBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardBottomSheet(
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
