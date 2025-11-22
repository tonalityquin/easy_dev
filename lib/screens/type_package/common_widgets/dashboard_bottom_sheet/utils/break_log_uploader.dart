// File: lib/screens/.../BreakLogUploader.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../repositories/commute_log_repository.dart';
import '../../../../../utils/api/sheet_upload_result.dart';
import '../../../../dev_package/debug_package/debug_database_logger.dart';

// ✅ DB 전용 로거

class BreakLogUploader {
  static const String _status = '휴게';

  // ─────────────────────────────────────────
  // 휴게 기록 저장 (Firestore 전용)
  // ─────────────────────────────────────────
  static Future<SheetUploadResult> uploadBreakJson({
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
        final msg = '휴게 기록 저장 실패: 필수 정보가 비어 있습니다.\n'
            'userId=$userId, name=$userName, area=$area, division=$division, time=$recordedTime';
        debugPrint('❌ $msg');

        await DebugDatabaseLogger().log(
          {
            'tag': 'BreakLogUploader.uploadBreakJson',
            'message': '휴게 기록 저장 실패 - 필수 정보 누락',
            'reason': 'validation_failed',
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'error',
          tags: const ['database', 'firestore', 'commute', 'break'],
        );

        return SheetUploadResult(success: false, message: msg);
      }

      final repo = CommuteLogRepository();

      // 2) ✅ 오늘 이미 휴게 로그가 있는지 확인
      final alreadyExists = await repo.hasLogForDate(
        status: _status,
        userId: userId,
        dateStr: dateStr,
      );

      if (alreadyExists) {
        const msg = '이미 오늘 휴게 기록이 있어, 새로 저장되지 않았습니다.';
        debugPrint('⚠️ $msg');
        // 중복은 의도된 제어 흐름이므로 에러 로그는 남기지 않음
        return const SheetUploadResult(success: false, message: msg);
      }

      // 3) ✅ Firestore commute_user_logs 에 기록
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

      final msg = '휴게 기록이 정상적으로 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');
      return SheetUploadResult(success: true, message: msg);
    } catch (e, st) {
      final msg = '휴게 기록 저장 중 오류가 발생했습니다.\n'
          '네트워크 상태나 Firebase 설정을 확인해 주세요.\n($e)';
      debugPrint('❌ $msg');

      await DebugDatabaseLogger().log(
        {
          'tag': 'BreakLogUploader.uploadBreakJson',
          'message': '휴게 기록 Firestore 저장 중 예외 발생',
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
        tags: const ['database', 'firestore', 'commute', 'break'],
      );

      return SheetUploadResult(success: false, message: msg);
    }
  }
}
