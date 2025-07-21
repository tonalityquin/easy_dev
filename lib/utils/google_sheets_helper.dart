import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';

class GoogleSheetsHelper {
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static String getSpreadsheetId(String area) {
    const spreadsheetMap = {
      'belivus': '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo',
      'pelican': '11VXQiw4bHpZHPmAd1GJHdao4d9C3zU4NmkEe81pv57I',
    };

    final trimmed = area.trim();
    final result = spreadsheetMap[trimmed];

    if (result == null) {
      print('[ERROR] Unknown area="$area", fallback to belivus');
    }

    return result ?? spreadsheetMap['belivus']!;
  }

  static Future<AutoRefreshingAuthClient> _getSheetsClient() async {
    final jsonString = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [SheetsApi.spreadsheetsScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  static List<List<String>> _convertRows(List<List<Object?>>? rawRows) {
    return rawRows?.map((row) => row.map((cell) => cell.toString()).toList()).toList() ?? [];
  }

  static Future<List<List<String>>> loadClockInOutRecords(String area) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final spreadsheetId = getSpreadsheetId(area);
    final result = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      '출퇴근기록!A2:G',
    );
    client.close();
    return _convertRows(result.values);
  }

  static Future<List<List<String>>> loadBreakRecords(String area) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final spreadsheetId = getSpreadsheetId(area);
    final result = await sheetsApi.spreadsheets.values.get(
      spreadsheetId,
      '휴게기록!A2:G',
    );
    client.close();
    return _convertRows(result.values);
  }

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

  static Future<void> createMonthlySummarySheet(String area, String sheetName) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final spreadsheetId = getSpreadsheetId(area);

    final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
    final sheets = spreadsheet.sheets ?? [];

    final List<Request> requests = [];

    final existingSheet = sheets.firstWhere(
      (sheet) => sheet.properties?.title == sheetName,
      orElse: () => Sheet(),
    );

    final sheetId = existingSheet.properties?.sheetId;
    if (sheetId != null) {
      requests.add(Request(deleteSheet: DeleteSheetRequest(sheetId: sheetId)));
    }

    requests.add(Request(
      addSheet: AddSheetRequest(properties: SheetProperties(title: sheetName)),
    ));

    await sheetsApi.spreadsheets.batchUpdate(
      BatchUpdateSpreadsheetRequest(requests: requests),
      spreadsheetId,
    );

    client.close();
  }

  static Future<void> writeMonthlyClockInOutSummary({
    required String area,
    required int year,
    required int month,
    required Map<String, String> userMap,
  }) async {
    final rows = await loadClockInOutRecords(area);

    final clockInMap = mapToCellData(
      rows,
      statusFilter: '출근',
      selectedYear: year,
      selectedMonth: month,
    );

    final clockOutMap = mapToCellData(
      rows,
      statusFilter: '퇴근',
      selectedYear: year,
      selectedMonth: month,
    );

    final List<List<Object>> sheetRows = [
      ['날짜', '이름', 'ID', '출근', '퇴근']
    ];
    final userIds = {...clockInMap.keys, ...clockOutMap.keys};

    for (int day = 1; day <= 31; day++) {
      final date = DateTime(year, month, day);
      if (date.month != month) break;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      for (final userId in userIds) {
        final name = userMap[userId] ?? '';
        final inTime = clockInMap[userId]?[day] ?? '';
        final outTime = clockOutMap[userId]?[day] ?? '';
        if (inTime.isEmpty && outTime.isEmpty) continue;

        sheetRows.add([dateStr, name, userId, inTime, outTime]);
      }
    }

    final sheetName = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')} 출퇴근';
    await createMonthlySummarySheet(area, sheetName);

    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    await sheetsApi.spreadsheets.values.update(
      ValueRange(values: sheetRows),
      getSpreadsheetId(area),
      '$sheetName!A1',
      valueInputOption: 'USER_ENTERED',
    );
    client.close();
  }

  static Future<void> writeMonthlyBreakSummary({
    required String area,
    required int year,
    required int month,
    required Map<String, String> userMap,
  }) async {
    final rows = await loadBreakRecords(area);

    final breakMap = mapToCellData(
      rows,
      statusFilter: '휴게',
      selectedYear: year,
      selectedMonth: month,
    );

    final List<List<Object>> sheetRows = [
      ['날짜', '이름', 'ID', '휴게']
    ];

    for (int day = 1; day <= 31; day++) {
      final date = DateTime(year, month, day);
      if (date.month != month) break;
      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      for (final userId in breakMap.keys) {
        final name = userMap[userId] ?? '';
        final breakTime = breakMap[userId]?[day] ?? '';
        if (breakTime.isEmpty) continue;

        sheetRows.add([dateStr, name, userId, breakTime]);
      }
    }

    final sheetName = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')} 휴게';
    await createMonthlySummarySheet(area, sheetName);

    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    await sheetsApi.spreadsheets.values.update(
      ValueRange(values: sheetRows),
      getSpreadsheetId(area),
      '$sheetName!A1',
      valueInputOption: 'USER_ENTERED',
    );
    client.close();
  }

  static Map<String, String> extractUserMap(List<List<String>> rows) {
    final Map<String, String> map = {};
    for (final row in rows) {
      if (row.length >= 4) {
        final id = row[2];
        final name = row[3];
        if (id.isNotEmpty && name.isNotEmpty) {
          map[id] = name;
        }
      }
    }
    return map;
  }

  static Future<void> updateClockInOutRecord({
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required String status,
    required String time,
  }) async {
    final spreadsheetId = getSpreadsheetId(area);
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

  static Future<void> updateBreakRecord({
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
    required String time,
  }) async {
    final spreadsheetId = getSpreadsheetId(area.trim());
    print('[DEBUG] updateBreakRecord: area=$area → spreadsheetId=$spreadsheetId');

    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final range = '휴게기록!A2:G';
    final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
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

      if (rowDate == targetDate && rowUserId == userId && rowStatus == status) {
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
