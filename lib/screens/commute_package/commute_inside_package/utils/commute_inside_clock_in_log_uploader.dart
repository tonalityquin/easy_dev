// lib/screens/.../commute_inside_package/utils/commute_inside_clock_in_log_uploader.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

// ✅ 중앙 OAuth 세션 재사용
import 'package:easydev/utils/google_auth_session.dart';

// ✅ 결과 타입
import 'package:easydev/utils/sheet_upload_result.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';
import '../../../../../utils/sheets_config.dart';
import '../../../dev_package/debug_package/debug_api_logger.dart';

class CommuteInsideClockInLogUploader {
  static const _sheetName = '출퇴근기록';
  static const String _status = '출근';

  // ─────────────────────────────────────────
  // Sheets API (중앙 세션 사용)
  // ─────────────────────────────────────────
  static Future<SheetsApi> _sheetsApi() async {
    final client = await GoogleAuthSession.instance.client();
    return SheetsApi(client);
  }

  // ─────────────────────────────────────────
  // 업로드/조회/URL 로직
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
    String? spreadsheetId;        // 설정이 없을 수도 있으므로 nullable 유지
    String recordedTime = '';

    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      area = (userState.user?.selectedArea ?? '').trim();
      division = areaState.currentDivision.trim();
      userId = (userState.user?.id ?? '').trim();
      userName = userState.name.trim();
      recordedTime = (data['recordedTime'] ?? '').toString().trim();

      // 1) 스프레드시트 ID 확인
      spreadsheetId = await SheetsConfig.getCommuteSheetId();
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        const msg =
            '출근 기록 업로드 실패: 출근부 스프레드시트 ID(commute_sheet_id)가 설정되지 않았습니다.\n'
            '관리자에게 출근부 스프레드시트 ID를 설정해 달라고 요청해 주세요.';
        debugPrint('❌ $msg');

        // 🔴 설정 누락도 운영 관점에서는 중요한 실패이므로 에러 로그 남김
        await DebugApiLogger().log(
          {
            'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
            'message': '출근 기록 업로드 실패 - 출근부 스프레드시트 ID(commute_sheet_id) 미설정',
            'reason': 'missing_spreadsheet_id',
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'error',
          tags: const ['sheets', 'commute', 'clock_in'],
        );

        return const SheetUploadResult(success: false, message: msg);
      }

      // 2) 날짜 / 시간 / 상태 구성 + 필수값 검증
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      if (userId.isEmpty ||
          userName.isEmpty ||
          area.isEmpty ||
          division.isEmpty ||
          recordedTime.isEmpty) {
        final msg =
            '출근 기록 업로드 실패: 필수 정보가 비어 있습니다.\n'
            'userId=$userId, name=$userName, area=$area, division=$division, time=$recordedTime';
        debugPrint('❌ $msg');

        // 🔴 필수 정보 누락도 추적 가능하도록 에러 로그
        await DebugApiLogger().log(
          {
            'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
            'message': '출근 기록 업로드 실패 - 필수 정보 누락',
            'reason': 'validation_failed',
            'userId': userId,
            'userName': userName,
            'area': area,
            'division': division,
            'recordedTime': recordedTime,
            'payload': data,
          },
          level: 'error',
          tags: const ['sheets', 'commute', 'clock_in'],
        );

        return SheetUploadResult(success: false, message: msg);
      }

      // 3) 중복 검사 (같은 날짜 + 같은 유저 + 출근)
      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate = existingRows.any(
            (row) =>
        row.length >= 7 &&
            row[0] == dateStr &&
            row[2] == userId &&
            row[6] == _status,
      );
      if (isDuplicate) {
        const msg = '이미 오늘 출근 기록이 있어, 새로 저장되지 않았습니다.';
        debugPrint('⚠️ $msg');
        // 🔸 의도된 제어 흐름(중복 방지)이므로 에러 로그는 남기지 않음
        return const SheetUploadResult(success: false, message: msg);
      }

      // 4) 업로드
      final row = <Object?>[
        dateStr,
        recordedTime,
        userId,
        userName,
        area,
        division,
        _status,
      ];

      final api = await _sheetsApi();
      await api.spreadsheets.values.append(
        ValueRange(values: [row]),
        spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      final msg = '출근 기록이 정상적으로 저장되었습니다. ($area / $division)';
      debugPrint('✅ $msg');
      return SheetUploadResult(success: true, message: msg);
    } catch (e, st) {
      final msg = '출근 기록 업로드 중 오류가 발생했습니다.\n'
          '네트워크 상태나 Google 로그인/권한을 확인해 주세요.\n($e)';
      debugPrint('❌ $msg');

      // 🔴 실제 예외(네트워크/권한 문제 등)는 API 로거에 상세히 기록
      await DebugApiLogger().log(
        {
          'tag': 'CommuteInsideClockInLogUploader.uploadAttendanceJson',
          'message': '출근 기록 업로드 중 예외 발생',
          'reason': 'exception',
          'error': e.toString(),
          'stack': st.toString(),
          'userId': userId,
          'userName': userName,
          'area': area,
          'division': division,
          'recordedTime': recordedTime,
          'spreadsheetId': spreadsheetId,
          'payload': data,
          'status': _status,
        },
        level: 'error',
        tags: const ['sheets', 'commute', 'clock_in'],
      );

      return SheetUploadResult(success: false, message: msg);
    }
  }

  static Future<List<List<String>>> _loadAllRecords(String spreadsheetId) async {
    final api = await _sheetsApi();
    final result = await api.spreadsheets.values.get(
      spreadsheetId,
      '$_sheetName!A2:G',
    );
    return result.values
        ?.map((row) => row.map((cell) => cell.toString()).toList())
        .toList() ??
        [];
  }

  /// 저장된 출근 시트 ID로 열람 URL을 돌려줍니다. (설정이 없으면 null)
  static Future<String?> getDownloadPath() async {
    final id = await SheetsConfig.getCommuteSheetId();
    if (id == null || id.isEmpty) return null;
    return 'https://docs.google.com/spreadsheets/d/$id/edit';
  }
}
