import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../utils/api/sheet_upload_result.dart';
import '../../../../single_mode/utils/att_brk_repository.dart';

class DoubleCommuteInClockInSave {
  static Future<SheetUploadResult> uploadAttendanceJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    String area = '';
    String division = '';

    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.user?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();

      // ✅ 약식 모드와 동일한 SQLite 테이블(simple_work_attendance)에 출근 기록 저장
      final now = DateTime.now();

      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workIn,
      );

      final msg = '출근 기록이 로컬에 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');

      return SheetUploadResult(success: true, message: msg);
    } catch (e) {
      final msg = '출근 기록 저장 중 오류가 발생했습니다.\n'
          '잠시 후 다시 시도해 주세요.\n($e)';
      debugPrint('❌ $msg');

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
