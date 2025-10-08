import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';

const kIsWorkingPrefsKey = 'isWorking';

class HomeDashBoardController {
  Future<void> handleWorkStatus(UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      showSuccessSnackbar(context, '퇴근 기록 업로드 완료');

      // ✅ 퇴근 상태를 로컬에 저장하고, 예약 알림을 즉시 취소
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, false);
      await EndtimeReminderService.instance.cancel();
    } else if (context.mounted) {
      showFailedSnackbar(context, '퇴근 기록 업로드 실패 또는 중복');
    }

    await FlutterForegroundTask.stopService();

    await userState.isHeWorking();
    await Future.delayed(const Duration(seconds: 1));

    SystemNavigator.pop();
  }
}
