// File: lib/screens/.../commute_inside_package/utils/commute_inside_clock_in_log_uploader.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../utils/api/sheet_upload_result.dart';
import '../../../dev_package/debug_package/debug_database_logger.dart';
import '../../../simple_package/utils/simple_mode/simple_mode_attendance_repository.dart';

class CommuteInsideClockInLogUploader {
  static const String _status = '출근';

  // ─────────────────────────────────────────
  // 출근 기록 저장 (SQLite 전용, 약식 모드와 동일 테이블 사용)
  //
  // - 이전: CommuteLogRepository + Firestore(commute_user_logs)에 기록
  // - 현재: SimpleModeAttendanceRepository.insertEvent(...) 만 호출
  //         → simple_work_attendance 테이블에 'work_in' 행 저장
  //
  // 반환 값은 그대로 SheetUploadResult 유지 (호출부 변경 최소화)
  // ─────────────────────────────────────────
  static Future<SheetUploadResult> uploadAttendanceJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    // 🔎 로그/디버깅용 컨텍스트 (예외 시 DebugDatabaseLogger에 남기기 위해 try 밖에서 선언)
    String area = '';
    String division = '';
    String userId = '';
    String userName = '';
    String recordedTime = '';

    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.user?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();
      userId = (userState.user?.id ?? '').trim();
      userName = userState.name.trim();
      recordedTime = (data['recordedTime'] ?? '').toString().trim();

      // 1) ✅ 약식 모드와 동일한 SQLite 테이블(simple_work_attendance)에 출근 기록 저장
      //
      //    - type: SimpleModeAttendanceType.workIn → 'work_in'
      //    - date/time: 현재 시각(DateTime.now())
      final now = DateTime.now();

      await SimpleModeAttendanceRepository.instance.insertEvent(
        dateTime: now,
        type: SimpleModeAttendanceType.workIn,
      );

      final msg = '출근 기록이 로컬에 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');

      // (선택) 성공 로그도 디버그 DB에 남김
      try {
        await DebugDatabaseLogger().log(
          {
            'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
            'message': '출근 기록 로컬(SQLite) 저장 완료',
            'status': _status,
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'info',
          tags: const ['database', 'sqlite', 'commute', 'clock_in'],
        );
      } catch (_) {}

      return SheetUploadResult(success: true, message: msg);
    } catch (e, st) {
      final msg = '출근 기록 저장 중 오류가 발생했습니다.\n'
          '잠시 후 다시 시도해 주세요.\n($e)';
      debugPrint('❌ $msg');

      try {
        await DebugDatabaseLogger().log(
          {
            'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
            'message': '출근 기록 SQLite 저장 중 예외 발생',
            'reason': 'exception',
            'error': e.toString(),
            'stack': st.toString(),
            'status': _status,
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'error',
          tags: const ['database', 'sqlite', 'commute', 'clock_in'],
        );
      } catch (_) {}

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
