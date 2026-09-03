import 'package:flutter/material.dart';

import '../../../../attendance/application/common_attendance_service.dart';
import '../../../applications/common/sheet_upload_result.dart';

class MinorClockOutSave {
  static Future<SheetUploadResult> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    final result = await CommonAttendanceService.clockOut(
      context,
      source: 'legacy_minor_clock_out_save',
      modeKey: 'minor',
    );
    return SheetUploadResult(
      success: result.success,
      message: result.message,
    );
  }
}
