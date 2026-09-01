import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../account/applications/user_state.dart';
import '../../applications/common/endtime_reminder_service.dart';
import '../../applications/common/break_record_result.dart';
import '../../applications/common/sheet_upload_result.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import 'utils/minor_clock_out_save.dart';
import 'utils/minor_break_save.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kIsWorkingPrefsKey = 'isWorking';

const kLastBreakDatePrefsKey = 'last_break_date';

class MinorHomeDashBoardController {
  Future<void> handleWorkStatus(
      UserState userState, BuildContext context) async {
    if (userState.isWorking) {
      final SheetUploadResult result = await _recordLeaveTime(context);

      if (result.success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kIsWorkingPrefsKey, false);
        await EndTimeReminderService.instance.cancel();
      } else {
        debugPrint('퇴근 기록 실패: ${result.message}');
      }

      await userState.isHeWorking();
    } else {
      await userState.isHeWorking();
    }
  }

  Future<SheetUploadResult> _recordLeaveTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final leaveData = <String, dynamic>{
        'userId': userState.session?.id ?? '',
        'userName': userState.name,
        'division': userState.session?.divisions.firstOrNull ?? '',
        'recordedTime': time,
      };

      final SheetUploadResult result = await MinorClockOutSave.uploadLeaveJson(
        context: context,
        data: leaveData,
      );
      return result;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 오류: $e');

      return const SheetUploadResult(
        success: false,
        message: '퇴근 기록 중 예기치 못한 오류가 발생했습니다. (컨트롤러)',
      );
    }
  }

  Future<BreakRecordResult> recordBreakTime(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);
      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final breakJson = <String, dynamic>{
        'userId': userState.session?.id ?? '',
        'userName': userState.name,
        'area': userState.area,
        'division': userState.session?.divisions.firstOrNull ?? '',
        'recordedTime': time,
        'status': '휴게',
      };

      final SheetUploadResult uploadResult = await MinorBreakSave.uploadBreakJson(
        context: context,
        data: breakJson,
      );

      if (!uploadResult.success) {
        debugPrint(
          '[minor_home_dash_board_controller] break_record_failed message=${uploadResult.message}',
        );
        return BreakRecordResult.failure(message: uploadResult.message);
      }

      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.breakTime,
      );
      final prefs = await SharedPreferences.getInstance();
      final String todayStr = _formatDate(now);
      await prefs.setString(kLastBreakDatePrefsKey, todayStr);
      debugPrint(
        '[minor_home_dash_board_controller] break_record_complete at=${now.toIso8601String()}',
      );
      return BreakRecordResult.success(
        recordedAt: now,
        message: uploadResult.message,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[minor_home_dash_board_controller] break_record_error error=$error',
      );
      debugPrint(stackTrace.toString());
      return BreakRecordResult.failure(
        message: '휴게 기록 중 오류가 발생했습니다: $error',
      );
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
