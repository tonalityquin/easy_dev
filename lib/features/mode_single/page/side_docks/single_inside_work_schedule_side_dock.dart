import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../application/single_inside_diagnostics.dart';
import '../widgets/single_inside_work_schedule_content_surface.dart';

class SingleInsideWorkScheduleSideDock extends StatelessWidget {
  const SingleInsideWorkScheduleSideDock({
    super.key,
    required this.area,
    required this.scheduleRevision,
    required this.onChanged,
    required this.onClose,
    required this.onDeveloperStatus,
    required this.onCloseEnabledChanged,
    required this.closeEnabled,
  });

  final String area;
  final int scheduleRevision;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final Future<void> Function() onDeveloperStatus;
  final ValueChanged<bool> onCloseEnabledChanged;
  final bool closeEnabled;

  @override
  Widget build(BuildContext context) {
    final areaLabel = area.trim().isEmpty ? '현재 근무지' : area.trim();
    return CommonSideDockFrame(
      title: '근무 일정',
      subtitle: areaLabel,
      icon: Icons.calendar_month_rounded,
      showCloseTooltip: false,
      closeEnabled: closeEnabled,
      onClose: onClose,
      onLongPress: () {
        SingleInsideDiagnostics.log(
          'status',
          'developer_status_request source=work_schedule_side_dock_header',
        );
        unawaited(onDeveloperStatus());
      },
      child: SingleInsideWorkScheduleContentSurface(
        scheduleRevision: scheduleRevision,
        onChanged: onChanged,
        onDeveloperStatus: onDeveloperStatus,
        showHeader: false,
        onCloseEnabledChanged: onCloseEnabledChanged,
      ),
    );
  }
}
