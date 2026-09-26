import 'package:flutter/material.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../dashboard/applications/common/sheet_upload_result.dart';
import 'commute_mode_spec.dart';

class CommuteClockInSave {
  static Future<SheetUploadResult> saveWorkIn({
    required BuildContext context,
    required CommuteModeSpec spec,
    String? logPrefix,
  }) async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '출근 저장 상태',
      initialMessage: '출근 저장과 근무 세션 생성을 시작합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '출근 저장을 진행합니다.',
      showDialogImmediately: false,
    );
    trace.log(
      'source=legacy_commute_clock_in_save context=${spec.contextKey} mode=${spec.modeKey} isHeadquarterContext=${spec.isHeadquarterContext}',
      progress: .12,
    );
    try {
      final result = await CommonAttendanceService.clockIn(
        context,
        source:
            'legacy_commute_clock_in_save:${spec.diagnosticKey}:${logPrefix?.trim() ?? ''}',
        modeKey: spec.modeKey,
        isHeadquarter: spec.isHeadquarterContext ? true : null,
        trace: trace,
      );
      if (result.success || result.alreadyRecorded) {
        await trace.succeed(result.message);
      } else {
        await trace.fail(result.message);
      }
      if (trace.developerMode && context.mounted) {
        await trace.showStatusDialog(context);
      }
      return SheetUploadResult(
        success: result.success,
        message: result.message,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '출근 저장 중 오류가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (trace.developerMode && context.mounted) {
        await trace.showStatusDialog(context);
      }
      return SheetUploadResult(
        success: false,
        message: '출근 저장 중 오류가 발생했습니다: $error',
      );
    }
  }
}
