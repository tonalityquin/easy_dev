import 'package:flutter/material.dart';

import '../widgets/hr/attendance_calendar.dart';
import '../widgets/hr/break_calendar.dart';
import '../widgets/hr/hr_time_dock_navigation.dart';

export '../widgets/hr/hr_time_dock_navigation.dart' show HrTimeDockTarget;

class HrTimeManagementDockCoordinator {
  HrTimeManagementDockCoordinator._();

  static bool _opening = false;

  static Future<void> show(
    BuildContext context, {
    required HrTimeDockTarget initialTarget,
    bool useRootNavigator = false,
    DateTime? initialMonth,
  }) async {
    if (_opening || !context.mounted) return;
    _opening = true;
    var request = HrTimeDockSwitchRequest(
      target: initialTarget,
      focusedMonth: normalizeHrTimeMonth(initialMonth ?? DateTime.now()),
    );
    HrTimeDockDebugLog.record(
      'open target=${request.target.name} month=${request.focusedMonth.year}-${request.focusedMonth.month.toString().padLeft(2, '0')} root=$useRootNavigator',
    );
    try {
      while (context.mounted) {
        final HrTimeDockSwitchRequest? next;
        switch (request.target) {
          case HrTimeDockTarget.attendance:
            next = await AttendanceCalendar.showAsLeftSideDock<HrTimeDockSwitchRequest>(
              context,
              useRootNavigator: useRootNavigator,
              initialMonth: request.focusedMonth,
            );
            break;
          case HrTimeDockTarget.breakTime:
            next = await BreakCalendar.showAsLeftSideDock<HrTimeDockSwitchRequest>(
              context,
              useRootNavigator: useRootNavigator,
              initialMonth: request.focusedMonth,
            );
            break;
        }
        if (next == null || !context.mounted) {
          HrTimeDockDebugLog.record('close target=${request.target.name}');
          return;
        }
        HrTimeDockDebugLog.record(
          'switch from=${request.target.name} to=${next.target.name} month=${next.focusedMonth.year}-${next.focusedMonth.month.toString().padLeft(2, '0')}',
        );
        request = HrTimeDockSwitchRequest(
          target: next.target,
          focusedMonth: normalizeHrTimeMonth(next.focusedMonth),
        );
        final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (!reduceMotion) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    } finally {
      _opening = false;
    }
  }
}
