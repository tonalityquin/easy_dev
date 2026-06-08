import 'package:flutter/material.dart';

import '../common/ops_dashboard_bottom_sheet.dart';
import 'widgets/triple_dashboard_punch_recorder_section.dart';

class TripleHomeDashBoardBottomSheet extends StatelessWidget {
  const TripleHomeDashBoardBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardBottomSheet(
      modeLabel: '기본형',
      modeIcon: Icons.view_week_rounded,
      punchRecorderBuilder: (context, userState, areaState) {
        return TripleDashboardInsidePunchRecorderSection(
          userId: userState.name,
          userName: userState.name,
          area: areaState.currentArea,
          division: areaState.currentDivision,
        );
      },
    );
  }
}
