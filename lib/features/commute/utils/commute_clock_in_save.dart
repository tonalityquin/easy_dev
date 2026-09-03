import 'package:flutter/material.dart';

import '../../attendance/application/common_attendance_service.dart';
import '../../dashboard/applications/common/sheet_upload_result.dart';

class CommuteClockInSave {
  static Future<SheetUploadResult> saveWorkIn({
    required BuildContext context,
    String? logPrefix,
  }) async {
    final result = await CommonAttendanceService.clockIn(
      context,
      source: 'legacy_commute_clock_in_save:${logPrefix?.trim() ?? ''}',
    );
    return SheetUploadResult(
      success: result.success,
      message: result.message,
    );
  }
}
