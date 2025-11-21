// File: lib/screens/.../commute_inside_package/utils/commute_inside_clock_in_log_uploader.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ✅ Firestore commute_user_logs 저장용 레포지토리
import 'package:easydev/repositories/commute_log_repository.dart';

// ✅ 결과 타입 (이름은 sheet_upload_result지만, 이제 Firestore 저장 결과로 사용)
import 'package:easydev/utils/sheet_upload_result.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';
import '../../../dev_package/debug_package/debug_database_logger.dart';

class CommuteInsideClockInLogUploader {
  static const String _status = '출근';

  // ─────────────────────────────────────────
  // 출근 기록 저장 (Firestore 전용)
  //
  // ❗ 중복 체크는 상위 레이어(UserState.hasClockInToday 등)에서 이미 수행하고,
  //    이 업로더는 "주어진 요청을 있는 그대로 기록"하는 역할만 담당합니다.
  // ─────────────────────────────────────────
  static Future<SheetUploadResult> uploadAttendanceJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    // 🔎 에러 로그용 컨텍스트(try 밖에 선언해서 catch에서도 사용)
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

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      // 1) 필수값 검증
      if (userId.isEmpty ||
          userName.isEmpty ||
          area.isEmpty ||
          division.isEmpty ||
          recordedTime.isEmpty) {
        final msg = '출근 기록 저장 실패: 필수 정보가 비어 있습니다.\n'
            'userId=$userId, name=$userName, area=$area, division=$division, time=$recordedTime';
        debugPrint('❌ $msg');

        await DebugDatabaseLogger().log(
          {
            'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
            'message': '출근 기록 저장 실패 - 필수 정보 누락',
            'reason': 'validation_failed',
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'error',
          tags: const ['database', 'firestore', 'commute', 'clock_in'],
        );

        return SheetUploadResult(success: false, message: msg);
      }

      final repo = CommuteLogRepository();

      // 🔁 (이전 코드)
      // 2) 오늘 이미 출근 로그가 있는지 확인 → hasLogForDate(...)
      //    ➜ 이 책임은 이제 UserState/Controller에서 담당하므로 제거

      // 2) ✅ Firestore commute_user_logs 에 기록
      await repo.addLog(
        status: _status,
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: recordedTime,
        dateTime: now,
      );

      final msg = '출근 기록이 정상적으로 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');
      return SheetUploadResult(success: true, message: msg);
    } catch (e, st) {
      final msg = '출근 기록 저장 중 오류가 발생했습니다.\n'
          '네트워크 상태나 Firebase 설정을 확인해 주세요.\n($e)';
      debugPrint('❌ $msg');

      await DebugDatabaseLogger().log(
        {
          'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
          'message': '출근 기록 Firestore 저장 중 예외 발생',
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
        tags: const ['database', 'firestore', 'commute', 'clock_in'],
      );

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
