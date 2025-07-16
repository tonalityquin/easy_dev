import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:intl/intl.dart';

class GoogleSheetsHelper {
  static const _spreadsheetId = '14qZa34Ha-y5Z6kj7eUqZxcP2CdLlaUQcyTJtLsyU_uo';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static Future<AutoRefreshingAuthClient> _getSheetsClient() async {
    final jsonString = await rootBundle.loadString(_serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [SheetsApi.spreadsheetsScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  static List<List<String>> _convertRows(List<List<Object?>>? rawRows) {
    return rawRows?.map((row) => row.map((cell) => cell.toString()).toList()).toList() ?? [];
  }

  static Future<List<List<String>>> loadClockInOutRecords() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
      '출퇴근기록!A2:G',
    );
    client.close();
    return _convertRows(result.values);
  }

  static Future<List<List<String>>> loadBreakRecords() async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    final result = await sheetsApi.spreadsheets.values.get(
      _spreadsheetId,
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

  /// 시트 존재 시 삭제 후 새로 생성
  static Future<void> createMonthlySummarySheet(String sheetName) async {
    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);

    final spreadsheet = await sheetsApi.spreadsheets.get(_spreadsheetId);
    final sheets = spreadsheet.sheets ?? [];

    final List<Request> requests = [];

    final existingSheet = sheets.firstWhere(
          (sheet) => sheet.properties?.title == sheetName,
      orElse: () => Sheet(),
    );

    final sheetId = existingSheet.properties?.sheetId;
    if (sheetId != null) {
      // 기존 시트 삭제 요청
      requests.add(Request(deleteSheet: DeleteSheetRequest(sheetId: sheetId)));
    }

    // 새 시트 추가 요청
    requests.add(Request(
      addSheet: AddSheetRequest(
        properties: SheetProperties(title: sheetName),
      ),
    ));

    await sheetsApi.spreadsheets.batchUpdate(
      BatchUpdateSpreadsheetRequest(requests: requests),
      _spreadsheetId,
    );

    client.close();
  }

  /// 출퇴근 통계 시트 작성
  static Future<void> writeMonthlyClockInOutSummary({
    required int year,
    required int month,
    required Map<String, String> userMap,
  }) async {
    final rows = await loadClockInOutRecords();

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

    final List<List<Object>> sheetRows = [];
    sheetRows.add(['날짜', '이름', 'ID', '출근', '퇴근']);

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
    await createMonthlySummarySheet(sheetName);

    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    await sheetsApi.spreadsheets.values.update(
      ValueRange(values: sheetRows),
      _spreadsheetId,
      '$sheetName!A1',
      valueInputOption: 'USER_ENTERED',
    );
    client.close();
  }

  /// 휴게 통계 시트 작성
  static Future<void> writeMonthlyBreakSummary({
    required int year,
    required int month,
    required Map<String, String> userMap,
  }) async {
    final rows = await loadBreakRecords();

    final breakMap = mapToCellData(
      rows,
      statusFilter: '휴게',
      selectedYear: year,
      selectedMonth: month,
    );

    final List<List<Object>> sheetRows = [];
    sheetRows.add(['날짜', '이름', 'ID', '휴게']);

    final userIds = breakMap.keys;

    for (int day = 1; day <= 31; day++) {
      final date = DateTime(year, month, day);
      if (date.month != month) break;

      final dateStr = DateFormat('yyyy-MM-dd').format(date);

      for (final userId in userIds) {
        final name = userMap[userId] ?? '';
        final breakTime = breakMap[userId]?[day] ?? '';
        if (breakTime.isEmpty) continue;

        sheetRows.add([dateStr, name, userId, breakTime]);
      }
    }

    final sheetName = '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')} 휴게';
    await createMonthlySummarySheet(sheetName);

    final client = await _getSheetsClient();
    final sheetsApi = SheetsApi(client);
    await sheetsApi.spreadsheets.values.update(
      ValueRange(values: sheetRows),
      _spreadsheetId,
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
}
