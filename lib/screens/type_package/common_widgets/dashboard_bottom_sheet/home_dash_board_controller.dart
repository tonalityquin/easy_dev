// lib/screens/type_package/common_widgets/dashboard_bottom_sheet/home_dash_board_controller.dart
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

// ⬇️ SheetUploadResult import (경로는 snackbar_helper 와 동일 depth)
import '../../../../../../utils/api/sheet_upload_result.dart';

const kIsWorkingPrefsKey = 'isWorking';

class HomeDashBoardController {
  Future<void> handleWorkStatus(UserState userState, BuildContext context) async {
    // ✅ 현재 근무 중인 상태에서 "퇴근하기" 버튼을 누른 경우
    if (userState.isWorking) {
      // ⬇️ 이제 bool 이 아니라 SheetUploadResult 사용
      final SheetUploadResult result = await _recordLeaveTime(context);

      if (!context.mounted) return;

      if (result.success) {
        // 업로더에서 만들어준 상세 메시지 사용
        showSuccessSnackbar(context, result.message);

        // ✅ 퇴근 상태를 로컬에 저장하고, 예약 알림을 즉시 취소
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kIsWorkingPrefsKey, false);
        await EndtimeReminderService.instance.cancel();
      } else {
        // 실패 사유를 그대로 노출 (예: "이미 오늘 퇴근 기록이 있습니다" 등)
        showFailedSnackbar(context, result.message);
      }

      // ✅ 포그라운드 서비스 종료
      await FlutterForegroundTask.stopService();

      // ✅ Firestore의 isWorking 상태 토글
      await userState.isHeWorking();

      // 약간의 딜레이 후 앱 종료 (기존 로직 유지)
      await Future.delayed(const Duration(seconds: 1));
      SystemNavigator.pop();
    } else {
      // 아직 근무 중이 아니면 단순히 isWorking 토글만 (출근/상태 변경)
      await userState.isHeWorking();
    }
  }

  /// 퇴근 시간 기록 → Sheets 업로드 호출
  /// 기존: Future<bool>  ▶▶  변경: Future<SheetUploadResult>
  Future<SheetUploadResult> _recordLeaveTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final leaveData = <String, dynamic>{
        'userId': userState.user?.id ?? '',
        'userName': userState.name,
        'division': userState.user?.divisions.first ?? '',
        'recordedTime': time,
      };

      // ⬇️ 이제 bool 이 아니라 SheetUploadResult 가 반환됨
      final SheetUploadResult result = await ClockOutLogUploader.uploadLeaveJson(
        context: context,
        data: leaveData,
      );
      return result;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 오류: $e');
      // 예외 상황도 SheetUploadResult 로 감싸서 리턴
      return const SheetUploadResult(
        success: false,
        message: '퇴근 기록 중 예기치 못한 오류가 발생했습니다. (컨트롤러)',
      );
    }
  }

  /// 휴게 시간 기록
  Future<void> recordBreakTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final breakJson = <String, dynamic>{
        'userId': userState.user?.id ?? '',
        'userName': userState.name,
        'area': userState.area,
        'division': userState.user?.divisions.first ?? '',
        'recordedTime': time,
        'status': '휴게',
      };

      // ⬇️ 이쪽도 bool 이 아니라 SheetUploadResult
      final SheetUploadResult result = await BreakLogUploader.uploadBreakJson(
        context: context,
        data: breakJson,
      );

      if (!context.mounted) return;

      if (result.success) {
        showSuccessSnackbar(context, result.message);
      } else {
        showFailedSnackbar(context, result.message);
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '휴게 기록 중 오류 발생: $e');
      }
    }
  }
}
