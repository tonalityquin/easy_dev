import 'package:flutter/material.dart';

import 'weekly_work_schedule_editor.dart';

class DashboardWorkScheduleSurface extends StatelessWidget {
  const DashboardWorkScheduleSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return const WeeklyWorkScheduleEditor(
      source: 'dashboard_surface',
    );
  }
}
