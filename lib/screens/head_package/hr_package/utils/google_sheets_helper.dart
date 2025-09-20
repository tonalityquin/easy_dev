// lib/screens/head_package/hr_package/utils/google_sheets_helper.dart
import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';

class GoogleSheetsHelper {
  static const _serviceAccountPath =
      'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  // ───────────────────────────────────────────────────────────────────────────
  // 인증 클라이언트
  // ───────────────────────────────────────────────────────────────────────────
  static Future<AutoRefreshingAuthClient> _getSheetsClient() async {
    final jsonString = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [SheetsApi.spreadsheetsScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 공통 유틸
  // ───────────────────────────────────────────────────────────────────────────
  static List<List<String>> _convertRows(List<List<Object?>>? rawRows) {
    return rawRows
        ?.map((row) => row.map((cell) => cell.toString()).toList())
        .toList() ??
        [];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 읽기 API (ID 직접 주입)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<List<List<String>>> loadClockInOutRecordsById(
      String spreadsheetId) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final result = await sheetsApi.spreadsheets.values
        .get(spreadsheetId, '출퇴근기록!A2:G');
    client.close();
    return _convertRows(result.values);
  }

  static Future<List<List<String>>> loadBreakRecordsById(
      String spreadsheetId) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final result =
    await sheetsApi.spreadsheets.values.get(spreadsheetId, '휴게기록!A2:G');
    client.close();
    return _convertRows(result.values);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 가공 유틸
  // ───────────────────────────────────────────────────────────────────────────
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

  // ───────────────────────────────────────────────────────────────────────────
  // 쓰기 API (ID 직접 주입)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> updateClockInOutRecordById({
    required String spreadsheetId,
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required String status, // '출근' | '퇴근'
    required String time,
  }) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final range = '출퇴근기록!A2:G';
    final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    final targetDate = DateFormat('yyyy-MM-dd').format(date);
    bool updated = false;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) continue;

      final rowDate = row[0];
      final rowUser = row[2];
      final rowStatus = row[6];

      if (rowDate == targetDate && rowUser == userId && rowStatus == status) {
        final cellRange = '출퇴근기록!B${i + 2}';
        await sheetsApi.spreadsheets.values.update(
          ValueRange(values: [
            [time]
          ]),
          spreadsheetId,
          cellRange,
          valueInputOption: 'USER_ENTERED',
        );
        updated = true;
        break;
      }
    }

    if (!updated) {
      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [
          [targetDate, time, userId, userName, area, division, status]
        ]),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }

    client.close();
  }

  static Future<void> updateBreakRecordById({
    required String spreadsheetId,
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required String time,
  }) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final range = '휴게기록!A2:G';
    final response =
    await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    final targetDate = DateFormat('yyyy-MM-dd').format(date);
    const status = '휴게';
    bool updated = false;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 7) continue;

      final rowDate = row[0];
      final rowUserId = row[2];
      final rowStatus = row[6];

      if (rowDate == targetDate &&
          rowUserId == userId &&
          rowStatus == status) {
        final cellRange = '휴게기록!B${i + 2}';
        await sheetsApi.spreadsheets.values.update(
          ValueRange(values: [
            [time]
          ]),
          spreadsheetId,
          cellRange,
          valueInputOption: 'USER_ENTERED',
        );
        updated = true;
        break;
      }
    }

    if (!updated) {
      await sheetsApi.spreadsheets.values.append(
        ValueRange(values: [
          [targetDate, time, userId, userName, area, division, status]
        ]),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }

    client.close();
  }
}
