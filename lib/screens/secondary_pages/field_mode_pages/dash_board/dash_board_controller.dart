import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import 'clock_out_log_uploader.dart';
import 'break_log_uploader.dart';

class DashBoardController {
  /// 출근 상태일 경우 퇴근 기록 및 종료
  Future<void> handleWorkStatus(UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      final success = await _recordLeaveTime(context);
      if (success && context.mounted) {
        showSuccessSnackbar(context, '퇴근 기록 업로드 완료');
      } else if (context.mounted) {
        showFailedSnackbar(context, '퇴근 기록 업로드 실패 또는 중복');
      }

      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      SystemNavigator.pop();
    } else {
      await userState.isHeWorking();
    }
  }

  /// ✅ 퇴근 시간 기록 및 업로드
  Future<bool> _recordLeaveTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final leaveJson = {
        'userId': userState.user?.id ?? '',
        'userName': userState.name,
        'area': userState.area,
        'division': userState.user?.divisions.first ?? '',
        'recordedTime': time,
        'status': '퇴근',
      };

      return await ClockOutLogUploader.uploadLeaveJson(
        context: context,
        data: leaveJson,
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

  Future<void> logout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.isHeWorking();
      await Future.delayed(const Duration(seconds: 1));
      await userState.clearUserToPhone();

      if (!context.mounted) return;

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }

    SystemChannels.platform.invokeMethod('SystemNavigator.pop');
  }
}
