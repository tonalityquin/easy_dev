import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';

class BreakLogUploader {
  static const _sheetName = '휴게기록';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// 선택된 지역에 따라 다른 Spreadsheet ID 반환
  static String _getSpreadsheetId(String area) {
    switch (area.toLowerCase()) {
      case 'pelican':
        return '11VXQiw4bHpZHPmAd1GJHdao4d9C3zU4NmkEe81pv57I'; // Pelican 시트 ID
      case 'belivus':
      default:
        return '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo'; // 기본: Belivus 시트 ID
    }
  }

  /// ✅ 휴게 기록 업로드
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

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final recordedTime = data['recordedTime'] ?? '';
      final status = '휴게';

      final spreadsheetId = _getSpreadsheetId(area);

      // ✅ [1] 중복 체크
      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate = existingRows.any((row) =>
      row.length >= 7 &&
          row[0] == dateStr &&
          row[2] == userId &&
          row[6] == status);

      if (isDuplicate) {
        debugPrint('⚠️ 이미 휴게 기록이 존재합니다.');
        return false;
      }

      // ✅ [2] 행 구성
      final row = [
        dateStr,
        recordedTime,
        userId,
        userName,
        area,
        division,
        status,
      ];

      final client = await _getSheetsClient();
      final sheetsApi = SheetsApi(client);

      // ✅ [3] Google Sheets에 추가
      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [row]),
        spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      client.close();

      debugPrint('✅ 휴게 기록 업로드 완료 (Google Sheets)');
      return true;
    } catch (e) {
      debugPrint('❌ 휴게 기록 업로드 실패: $e');
      return false;
    }
  }

  /// 🔐 인증 클라이언트 생성
  static Future<AuthClient> _getSheetsClient() async {
    final jsonStr = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonStr);
    return await clientViaServiceAccount(
      credentials,
      [SheetsApi.spreadsheetsScope],
    );
  }

  /// 📥 휴게기록 시트 불러오기
  static Future<List<List<String>>> _loadAllRecords(String spreadsheetId) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      '$_sheetName!A2:G',
    );

    client.close();

    return result.values?.map((row) => row.map((cell) => cell.toString()).toList()).toList() ?? [];
  }

  /// 다운로드 링크
  static String getDownloadPath({
    required String area,
  }) {
    return 'https://docs.google.com/spreadsheets/d/${_getSpreadsheetId(area)}/edit';
  }
}
