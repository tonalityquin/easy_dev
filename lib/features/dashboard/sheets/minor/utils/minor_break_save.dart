import 'package:flutter/material.dart';

import '../../../../attendance/application/common_attendance_service.dart';
import '../../../applications/common/sheet_upload_result.dart';

class MinorBreakSave {
  static Future<SheetUploadResult> uploadBreakJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    final result = await CommonAttendanceService.recordBreak(
      context,
      source: 'legacy_minor_break_save',
      modeKey: 'minor',
    );
    return SheetUploadResult(
      success: result.success,
      message: result.message,
    );
  }
}
