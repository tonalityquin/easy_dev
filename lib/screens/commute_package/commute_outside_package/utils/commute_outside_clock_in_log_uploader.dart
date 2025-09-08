import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../../../states/area/area_state.dart';
import '../../../../../states/user/user_state.dart';

class CommuteOutsideClockInLogUploader {
  static const _sheetName = '출퇴근기록';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static String _getSpreadsheetId(String area) {
    switch (area.toLowerCase()) {
      case 'pelican':
        return '11VXQiw4bHpZHPmAd1GJHdao4d9C3zU4NmkEe81pv57I'; // pelican
      case 'belivus':
      default:
        return '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo'; // belivus
    }
  }

  static Future<bool> uploadAttendanceJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = userState.user?.selectedArea ?? '';
      final spreadsheetId = _getSpreadsheetId(area);
      final division = areaState.currentDivision;
      final userId = userState.user?.id ?? '';
      final userName = userState.name;

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final recordedTime = data['recordedTime'] ?? '';
      final status = '출근';

      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate = existingRows.any((row) =>
      row.length >= 7 &&
          row[0] == dateStr &&
          row[2] == userId &&
          row[6] == status,
      );

      if (isDuplicate) {
        debugPrint('⚠️ 이미 출근 기록이 존재합니다.');
        return false;
      }

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

      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [row]),
        spreadsheetId,
        '$_sheetName!A1',
        valueInputOption: 'USER_ENTERED',
      );

      client.close();

      debugPrint('✅ 출근 기록 업로드 완료 (Google Sheets)');
      return true;
    } catch (e) {
      debugPrint('❌ 출근 기록 업로드 실패: $e');
      return false;
    }
  }

  static Future<AuthClient> _getSheetsClient() async {
    final jsonStr = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonStr);
    return await clientViaServiceAccount(
      credentials,
      [SheetsApi.spreadsheetsScope],
    );
  }

  static Future<List<List<String>>> _loadAllRecords(String spreadsheetId) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      '$_sheetName!A2:G',
    );

    client.close();

    return result.values?.map((row) =>
        row.map((cell) => cell.toString()).toList()
    ).toList() ?? [];
  }

  static String getDownloadPath({
    required String area,
  }) {
    final id = _getSpreadsheetId(area);
    return 'https://docs.google.com/spreadsheets/d/$id/edit';
  }
}
