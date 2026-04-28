import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../features/account/applications/user_state.dart';
import '../../../../../../features/dashboard/applications/common/sheet_upload_result.dart';
import '../../../../../../features/dev/application/area_state.dart';
import '../../../../../../features/mode_single/application/att_brk_repository.dart';

class MinorClockOutSave {
  static Future<SheetUploadResult> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    String area = '';
    String division = '';
    String userId = '';
    String userName = '';
    String recordedTime = '';

    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.session?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();
      userId = (userState.session?.id ?? '').trim();
      userName = userState.name.trim();
      recordedTime = (data['recordedTime'] ?? '').toString().trim();

      if (userId.isEmpty ||
          userName.isEmpty ||
          area.isEmpty ||
          division.isEmpty ||
          recordedTime.isEmpty) {
        final msg = '퇴근 기록 저장 실패: 필수 정보가 비어 있습니다.\n'
            'userId=$userId, name=$userName, area=$area, division=$division, time=$recordedTime';
        debugPrint('❌ $msg');

        return SheetUploadResult(success: false, message: msg);
      }

      final now = DateTime.now();

      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workOut,
      );

      final msg = '퇴근 기록이 로컬에 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');

      return SheetUploadResult(success: true, message: msg);
    } catch (e) {
      final msg = '퇴근 기록 저장 중 오류가 발생했습니다.\n'
          '잠시 후 다시 시도해 주세요.\n($e)';
      debugPrint('❌ $msg');

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
