// File: lib/screens/.../ClockOutLogUploader.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ✅ UserState / AreaState 사용
import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';

import '../../../../../utils/api/sheet_upload_result.dart';
import '../../../../dev_package/debug_package/debug_database_logger.dart';
import '../../../../simple_package/utils/simple_mode/simple_mode_attendance_repository.dart';

// ✅ DB 전용 로거

class ClockOutLogUploader {
  static const String _status = '퇴근';

  // ─────────────────────────────────────────
  // 퇴근 기록 저장 (SQLite 전용, 약식 모드와 동일 테이블 사용)
  //
  // - 이전: CommuteLogRepository + Firestore(commute_user_logs)에 기록
  // - 현재: SimpleModeAttendanceRepository.insertEvent(...) 만 호출
  //         → simple_work_attendance 테이블에 'work_out' 1행 저장
  // ─────────────────────────────────────────
  static Future<SheetUploadResult> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    // 🔎 에러 로그용 컨텍스트(try 밖에 선언)
    String area = '';
    String division = '';
    String userId = '';
    String userName = '';
    String recordedTime = '';

    try {
      // ✅ UserState / AreaState 에서 정보 읽기
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.user?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();
      userId = (userState.user?.id ?? '').trim();
      userName = userState.name.trim();
      recordedTime = (data['recordedTime'] ?? '').toString().trim();

      // 1) 필수값 검증
      if (userId.isEmpty ||
          userName.isEmpty ||
          area.isEmpty ||
          division.isEmpty ||
          recordedTime.isEmpty) {
        final msg = '퇴근 기록 저장 실패: 필수 정보가 비어 있습니다.\n'
            'userId=$userId, name=$userName, area=$area, division=$division, time=$recordedTime';
        debugPrint('❌ $msg');

        await DebugDatabaseLogger().log(
          {
            'tag': 'ClockOutLogUploader.uploadLeaveJson',
            'message': '퇴근 기록 저장 실패 - 필수 정보 누락',
            'reason': 'validation_failed',
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
            'status': _status,
          },
          level: 'error',
          tags: const ['database', 'sqlite', 'commute', 'clock_out'],
        );

        return SheetUploadResult(success: false, message: msg);
      }

      // 2) ✅ 약식 모드와 동일한 SQLite 테이블(simple_work_attendance)에 저장
      //
      //    - type: SimpleModeAttendanceType.workOut → 'work_out'
      //    - date: yyyy-MM-dd
      //    - time: HH:mm
      final now = DateTime.now();

      await SimpleModeAttendanceRepository.instance.insertEvent(
        dateTime: now,
        type: SimpleModeAttendanceType.workOut,
      );

      final msg = '퇴근 기록이 로컬에 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');

      try {
        await DebugDatabaseLogger().log(
          {
            'tag': 'ClockOutLogUploader.uploadLeaveJson',
            'message': '퇴근 기록 로컬(SQLite) 저장 완료',
            'status': _status,
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'info',
          tags: const ['database', 'sqlite', 'commute', 'clock_out'],
        );
      } catch (_) {}

      return SheetUploadResult(success: true, message: msg);
    } catch (e, st) {
      final msg = '퇴근 기록 저장 중 오류가 발생했습니다.\n'
          '잠시 후 다시 시도해 주세요.\n($e)';
      debugPrint('❌ $msg');

      try {
        await DebugDatabaseLogger().log(
          {
            'tag': 'ClockOutLogUploader.uploadLeaveJson',
            'message': '퇴근 기록 SQLite 저장 중 예외 발생',
            'reason': 'exception',
            'error': e.toString(),
            'stack': st.toString(),
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
            'status': _status,
          },
          level: 'error',
          tags: const ['database', 'sqlite', 'commute', 'clock_out'],
        );
      } catch (_) {}

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
