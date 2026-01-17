import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/snackbar_helper.dart';
import 'utils/triple_clock_out_save.dart';
import 'utils/triple_break_save.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';

// ⬇️ SheetUploadResult import (경로는 snackbar_helper 와 동일 depth)
import '../../../../../../utils/api/sheet_upload_result.dart';

const kIsWorkingPrefsKey = 'isWorking';

/// 🔹 오늘 휴게 버튼을 눌렀는지 확인하기 위한 날짜 저장 키
///    예: '2025-11-29' 같은 문자열이 들어감
const kLastBreakDatePrefsKey = 'last_break_date';

class TripleHomeDashBoardController {
  Future<void> handleWorkStatus(
      UserState userState, BuildContext context) async {
    // ✅ 현재 근무 중인 상태에서 "퇴근하기" 버튼을 누른 경우
    if (userState.isWorking) {
      // ⬇️ SQLite 업로더 사용 (ClockOutLogUploader → SimpleModeAttendanceRepository)
      final SheetUploadResult result = await _recordLeaveTime(context);

      if (!context.mounted) return;

      if (result.success) {
        // 업로더에서 만들어준 상세 메시지 사용
        showSuccessSnackbar(context, result.message);

        // ✅ 퇴근 상태를 로컬에 저장하고, 예약 알림을 즉시 취소
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kIsWorkingPrefsKey, false);
        await EndTimeReminderService.instance.cancel();
      } else {
        // 실패 사유를 그대로 노출
        showFailedSnackbar(context, result.message);
      }

      // ✅ Firestore의 isWorking 상태 토글(근무 상태 플래그만 변경)
      await userState.isHeWorking();

      // ⚠️ 앱 종료 / 포그라운드 서비스 중지는
      //    HqDashBoardPage / HomeDashBoardBottomSheet 의
      //    _exitAppAfterClockOut(...) 에서 일괄 처리합니다.
    } else {
      // 아직 근무 중이 아니면 단순히 isWorking 토글만 (출근/상태 변경)
      await userState.isHeWorking();
    }
  }

  /// 퇴근 시간 기록 → 로컬(SQLite) 기록 헬퍼 호출
  ///
  /// - 내부에서는 ClockOutLogUploader.uploadLeaveJson(...) 을 호출하고
  ///   그 안에서 SimpleModeAttendanceRepository.insertEvent(...) 를 통해
  ///   simple_work_attendance 테이블에 'work_out' 행을 저장합니다.
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

      // ⬇️ 여기서부터는 SQLite 기반 업로더가 처리
      final SheetUploadResult result =
      await TripleClockOutSave.uploadLeaveJson(
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
  ///
  /// - BreakLogUploader.uploadBreakJson(...) 에서
  ///   SimpleModeAttendanceRepository.insertEvent(...) 를 통해
  ///   simple_break_attendance 테이블에 'break' 행을 저장합니다.
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

      // ⬇️ 이쪽도 SQLite 기반 업로더 사용
      final SheetUploadResult result = await TripleBreakSave.uploadBreakJson(
        context: context,
        data: breakJson,
      );

      if (!context.mounted) return;

      if (result.success) {
        showSuccessSnackbar(context, result.message);

        // 🔹 여기서 오늘 날짜를 SharedPreferences 에 저장
        //
        //  - 저장 방식: 'YYYY-MM-DD' 문자열
        //  - 키: kLastBreakDatePrefsKey ('last_break_date')
        //  - 오버레이에서는 이 값을 꺼내서 "오늘 날짜와 같은지" 비교해서
        //    오늘 휴게를 눌렀는지 판단하면 됨.
        final prefs = await SharedPreferences.getInstance();
        final String todayStr = _formatDate(DateTime.now());
        await prefs.setString(kLastBreakDatePrefsKey, todayStr);
      } else {
        showFailedSnackbar(context, result.message);
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '휴게 기록 중 오류 발생: $e');
      }
    }
  }

  /// 'YYYY-MM-DD' 형식으로 날짜 문자열 생성
  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
