import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../account/applications/user_state.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import '../../applications/common/endtime_reminder_service.dart';

class SingleHomeDashBoardController {
  Future<void> handleWorkStatus(
    UserState userState,
    BuildContext context,
  ) async {
    if (!userState.isWorking) {
      await userState.isHeWorking();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isWorking', false);
    await EndTimeReminderService.instance.cancel();
    await userState.isHeWorking();
    debugPrint(
      '[SingleHomeDashBoardController] clockout_local_state_updated isWorking=${userState.isWorking}',
    );
  }

  Future<void> recordBreakTime(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final session = userState.session;
    if (session == null) {
      debugPrint('[SingleHomeDashBoardController] break_skipped session=null');
      return;
    }

    final now = DateTime.now();
    await AttBrkRepository.instance.insertEventAndUpload(
      dateTime: now,
      type: AttBrkModeType.breakTime,
      userId: session.id,
      userName: session.displayName,
      area: userState.currentArea,
      division: userState.division,
    );

    final prefs = await SharedPreferences.getInstance();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await prefs.setString('last_break_date', date);
    debugPrint(
      '[SingleHomeDashBoardController] break_recorded at=${now.toIso8601String()} area=${userState.currentArea} division=${userState.division}',
    );
  }
}
