import 'package:flutter/material.dart';

import '../common/ops_dashboard_side_dock.dart';
import '../../sheets/triple/widgets/triple_dashboard_punch_recorder_section.dart';

class TripleHomeDashboardSideDock extends StatelessWidget {
  const TripleHomeDashboardSideDock({super.key});

  @override
  Widget build(BuildContext context) {
    return OpsDashboardSideDock(
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
