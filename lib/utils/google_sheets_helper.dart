import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';

class GoogleSheetsHelper {
  static const _spreadsheetId = '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo'; // 시트 ID
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// 인증된 Sheets API 클라이언트 생성
  static Future<AutoRefreshingAuthClient> _getSheetsClient() async {
    final jsonString = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [SheetsApi.spreadsheetsReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  /// 공통 로드 함수: Object? 리스트를 String 리스트로 변환
  static List<List<String>> _convertRows(List<List<Object?>>? rawRows) {
    return rawRows
        ?.map((row) => row.map((cell) => cell.toString()).toList())
        .toList() ??
        [];
  }

  /// 출근기록 시트
  static Future<List<List<String>>> loadClockInRows() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
      '출근기록!A2:G',
    );

    client.close();
    return _convertRows(result.values);
  }

  /// 퇴근기록 시트
  static Future<List<List<String>>> loadClockOutRows() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
      '퇴근기록!A2:G',
    );

    client.close();
    return _convertRows(result.values);
  }

  /// 휴게기록 시트
  static Future<List<List<String>>> loadBreakRows() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
      '휴게기록!A2:G',
    );

    client.close();
    return _convertRows(result.values);
  }

  /// 시트 데이터 → Map<userId, Map<day, time>>
  static Map<String, Map<int, String>> mapToCellData(
      List<List<String>> rows, {
        required String statusFilter,
        int? selectedYear,
        int? selectedMonth,
        String suffixForKey = '',
      }) {
    final Map<String, Map<int, String>> data = {};

    for (final row in rows) {
      if (row.length < 7) continue;

      final dateStr = row[0];
      final time = row[1];
      final userId = row[2];
      final status = row[6];

      if (status != statusFilter) continue;

      DateTime? date;
      try {
        date = DateFormat('yyyy-MM-dd').parse(dateStr);
      } catch (_) {
        continue;
      }

      if (selectedYear != null && date.year != selectedYear) continue;
      if (selectedMonth != null && date.month != selectedMonth) continue;

      final day = date.day;
      final key = '$userId$suffixForKey';

      data.putIfAbsent(key, () => {});
      data[key]![day] = time;
    }

    return data;
  }
}
