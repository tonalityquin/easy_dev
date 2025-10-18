// lib/screens/.../ClockOutLogUploader.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ 중앙 OAuth 세션 재사용
import 'package:easydev/utils/google_auth_session.dart';

import '../../../../../utils/sheets_config.dart';

class ClockOutLogUploader {
  static const _sheetName = '출퇴근기록';

  // ─────────────────────────────────────────
  // Sheets API (중앙 세션 사용)
  // ─────────────────────────────────────────
  static Future<SheetsApi> _sheetsApi() async {
    final client = await GoogleAuthSession.instance.client();
    return SheetsApi(client);
  }

  // ─────────────────────────────────────────
  // 업로드/조회 로직
  // ─────────────────────────────────────────
  static Future<bool> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedArea = prefs.getString('selectedArea')?.trim() ?? '';

      final spreadsheetId = await SheetsConfig.getCommuteSheetId();
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        debugPrint('❌ 퇴근 업로드 실패: 스프레드시트 ID가 설정되지 않았습니다. (commute_sheet_id)');
        return false;
      }

      final userName = data['userName']?.toString().trim() ?? '';
      final userId = data['userId']?.toString().trim() ?? '';
      final division = data['division']?.toString().trim() ?? '';
      final recordedTime = data['recordedTime']?.toString().trim() ?? '';

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      const status = '퇴근';
      final area = selectedArea;

      if (userId.isEmpty || userName.isEmpty || division.isEmpty || recordedTime.isEmpty) {
        debugPrint(
            '❌ 필수 항목 누락: userId=$userId, userName=$userName, division=$division, recordedTime=$recordedTime');
        return false;
      }

      // 중복 검사
      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate = existingRows.any(
            (row) =>
        row.length >= 7 &&
            row[0] == dateStr &&
            row[2] == userId &&
            row[6] == status,
      );
      if (isDuplicate) {
        debugPrint('⚠️ 이미 퇴근 기록이 존재합니다.');
        return false;
      }

      // 업로드
      final row = [dateStr, recordedTime, userId, userName, area, division, status];
      final api = await _sheetsApi();
      await api.spreadsheets.values.append(
        ValueRange(values: [row]),
        spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      debugPrint('✅ 퇴근 기록 업로드 완료 ($area)');
      return true;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 업로드 실패: $e');
      return false;
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
}
