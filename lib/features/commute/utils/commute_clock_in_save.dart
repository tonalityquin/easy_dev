import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../utils/auth/sheet_upload_result.dart';
import '../../dev/application/area_state.dart';
import '../../mode_single/application/att_brk_repository.dart';

class CommuteClockInSave {
  static Future<SheetUploadResult> saveWorkIn({
    required BuildContext context,
    String? logPrefix,
  }) async {
    String area = '';
    String division = '';

    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.session?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();

      final now = DateTime.now();

      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workIn,
      );

      final msg = '출근 기록이 로컬에 저장되었습니다. ($area / $division)';
      debugPrint(_applyPrefix(logPrefix, '✅ $msg'));

      return SheetUploadResult(success: true, message: msg);
    } catch (e) {
      final msg = '출근 기록 저장 중 오류가 발생했습니다.\n잠시 후 다시 시도해 주세요.\n($e)';
      debugPrint(_applyPrefix(logPrefix, '❌ $msg'));

      return SheetUploadResult(success: false, message: msg);
    }
  }

  static String _applyPrefix(String? prefix, String message) {
    if (prefix == null || prefix.isEmpty) {
      return message;
    }
    return '[$prefix] $message';
  }
}
