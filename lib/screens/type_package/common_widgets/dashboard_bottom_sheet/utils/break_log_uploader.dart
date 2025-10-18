// lib/screens/.../BreakLogUploader.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// ✅ 중앙 OAuth 세션 재사용
import 'package:easydev/utils/google_auth_session.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../utils/sheets_config.dart';

class BreakLogUploader {
  static const _sheetName = '휴게기록';

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
  static Future<bool> uploadBreakJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = userState.user?.selectedArea ?? '';
      final division = areaState.currentDivision;
      final userId = userState.user?.id ?? '';
      final userName = userState.name;

      final spreadsheetId = await SheetsConfig.getCommuteSheetId();
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        debugPrint('❌ 휴게 업로드 실패: 스프레드시트 ID가 설정되지 않았습니다. (commute_sheet_id)');
        return false;
      }

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final recordedTime = data['recordedTime'] ?? '';
      const status = '휴게';

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
        debugPrint('⚠️ 이미 휴게 기록이 존재합니다.');
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

      debugPrint('✅ 휴게 기록 업로드 완료 (Google Sheets)');
      return true;
    } catch (e) {
      debugPrint('❌ 휴게 기록 업로드 실패: $e');
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
