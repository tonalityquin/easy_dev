import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CommuteOutsideClockOutLogUploader {
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';
  static const _sheetName = '출퇴근기록';

  static const Map<String, String> spreadsheetMap = {
    'belivus': '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo',
    'pelican': '11VXQiw4bHpZHPmAd1GJHdao4d9C3zU4NmkEe81pv57I',
  };

  static Future<bool> uploadLeaveJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final selectedArea = prefs.getString('selectedArea')?.trim() ?? 'belivus';
      final spreadsheetId = spreadsheetMap[selectedArea] ?? spreadsheetMap['belivus']!;

      final userName = data['userName']?.toString().trim() ?? '';
      final userId = data['userId']?.toString().trim() ?? '';
      final division = data['division']?.toString().trim() ?? '';
      final recordedTime = data['recordedTime']?.toString().trim() ?? '';
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      const status = '퇴근';

      final area = selectedArea;

      if (userId.isEmpty || userName.isEmpty || division.isEmpty || recordedTime.isEmpty) {
        debugPrint('❌ 필수 항목 누락: userId=$userId, userName=$userName, division=$division, recordedTime=$recordedTime');
        return false;
      }

      final existingRows = await _loadAllRecords(spreadsheetId);
      final isDuplicate =
          existingRows.any((row) => row.length >= 7 && row[0] == dateStr && row[2] == userId && row[6] == status);

      if (isDuplicate) {
        debugPrint('⚠️ 이미 퇴근 기록이 존재합니다.');
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
      debugPrint('✅ 퇴근 기록 업로드 완료 ($selectedArea)');
      return true;
    } catch (e) {
      debugPrint('❌ 퇴근 기록 업로드 실패: $e');
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

    return result.values?.map((row) => row.map((cell) => cell.toString()).toList()).toList() ?? [];
  }
}
