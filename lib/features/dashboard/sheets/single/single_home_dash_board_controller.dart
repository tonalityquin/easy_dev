import 'package:flutter/material.dart';

import '../../../account/applications/user_state.dart';
import '../../../attendance/application/common_attendance_service.dart';
import '../../applications/common/break_record_result.dart';

class SingleHomeDashBoardController {
  Future<void> handleWorkStatus(
    UserState userState,
    BuildContext context,
  ) async {
    if (!userState.isWorking) {
      debugPrint(
        '[SingleHomeDashBoardController] work_status_ignored reason=clock_in_requires_common_gate',
      );
      return;
    }
    final result = await CommonAttendanceService.clockOut(
      context,
      source: 'single_home_dashboard_controller',
      modeKey: 'single',
    );
    if (!result.success) {
      debugPrint(
        '[SingleHomeDashBoardController] clock_out_failed message=${result.message}',
      );
    }
  }

  Future<BreakRecordResult> recordBreakTime(BuildContext context) async {
    final result = await CommonAttendanceService.recordBreak(
      context,
      source: 'single_home_dashboard_controller',
      modeKey: 'single',
    );
    final recordedAt = result.recordedAt;
    if (!result.success || recordedAt == null) {
      return BreakRecordResult.failure(message: result.message);
    }
    return BreakRecordResult.success(
      recordedAt: recordedAt,
      message: result.message,
    );
  }
}
