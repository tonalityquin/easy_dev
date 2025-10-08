import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';


import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import 'utils/clock_out_log_uploader.dart';
import 'utils/break_log_uploader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';
const kIsWorkingPrefsKey = 'isWorking';


class HomeDashBoardController {
  Future<void> handleWorkStatus(UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      final success = await _recordLeaveTime(context);
      if (success && context.mounted) {
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
    } else {
      await userState.isHeWorking();
    }
  }


  Future<bool> _recordLeaveTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);


      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';


      final leaveData = {
        'userId': userState.user?.id ?? '',
        'userName': userState.name,
        'division': userState.user?.divisions.first ?? '',
        'recordedTime': time,
      };


      return await ClockOutLogUploader.uploadLeaveJson(
        context: context,
        data: leaveData,
      );
    } catch (e) {
      debugPrint('❌ 퇴근 기록 오류: $e');
      return false;
    }
  }


  Future<void> recordBreakTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';


      final breakJson = {
        'userId': userState.user?.id ?? '',
        'userName': userState.name,
        'area': userState.area,
        'division': userState.user?.divisions.first ?? '',
        'recordedTime': time,
        'status': '휴게',
      };


      final success = await BreakLogUploader.uploadBreakJson(
        context: context,
        data: breakJson,
      );


      if (context.mounted) {
        if (success) {
          showSuccessSnackbar(context, '휴게 기록 업로드 완료');
        } else {
          showFailedSnackbar(context, '휴게 기록 업로드 실패 또는 중복');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '휴게 기록 중 오류 발생: $e');
      }
    }
  }


// logout(BuildContext) 메서드는 삭제되었습니다.
}
