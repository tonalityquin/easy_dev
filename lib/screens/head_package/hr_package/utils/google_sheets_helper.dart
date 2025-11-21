// lib/screens/head_package/hr_package/utils/google_sheets_helper.dart
import 'dart:async';
import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';

// ✅ 중앙 인증 세션만 사용 (OAuth 팝업을 최초 1회로 제한)
import 'package:easydev/utils/google_auth_session.dart';

/// 출퇴근 배치 저장용 모델
class ClockRow {
  final DateTime date;
  final String userId;
  final String userName;
  final String area;
  final String division;
  final String status; // '출근' | '퇴근'
  final String time;   // 'HH:mm'
  ClockRow({
    required this.date,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.status,
    required this.time,
  });
}

/// 휴게 배치 저장용 모델
class BreakRow {
  final DateTime date;
  final String userId;
  final String userName;
  final String area;
  final String division;
  final String time;   // 'HH:mm'
  const BreakRow({
    required this.date,
    required this.userId,
    required this.userName,
    required this.area,
    required this.division,
    required this.time,
  });
}

class GoogleSheetsHelper {
  // ───────────────────────────────────────────────────────────────────────────
  // 중앙 세션 기반 Sheets API 획득 (모든 메서드가 이것만 사용)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<SheetsApi> _sheetsApi() async {
    final client = await GoogleAuthSession.instance.safeClient();
    return SheetsApi(client);
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
    final api = await _sheetsApi();
    final res =
    await api.spreadsheets.values.get(spreadsheetId, '출퇴근기록!A2:G');
    return _convertRows(res.values);
  }

  static Future<List<List<String>>> loadBreakRecordsById(
      String spreadsheetId) async {
    final api = await _sheetsApi();
    final res = await api.spreadsheets.values.get(spreadsheetId, '휴게기록!A2:G');
    return _convertRows(res.values);
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
  // 쓰기 API (단건 upsert) — 기존 시그니처 유지
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
    final api = await _sheetsApi();

    const range = '출퇴근기록!A2:G';
    final response = await api.spreadsheets.values.get(spreadsheetId, range);
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
        await api.spreadsheets.values.update(
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
      await api.spreadsheets.values.append(
        ValueRange(values: [
          [targetDate, time, userId, userName, area, division, status]
        ]),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }
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
    final api = await _sheetsApi();

    const range = '휴게기록!A2:G';
    final response = await api.spreadsheets.values.get(spreadsheetId, range);
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
        await api.spreadsheets.values.update(
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
      await api.spreadsheets.values.append(
        ValueRange(values: [
          [targetDate, time, userId, userName, area, division, status]
        ]),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 배치 업서트 API (출퇴근)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> upsertClockInOutBatchById({
    required String spreadsheetId,
    required List<ClockRow> rows,
  }) async {
    if (rows.isEmpty) return;

    final api = await _sheetsApi();
    const range = '출퇴근기록!A2:G';

    // 1) 현재 범위 한 번만 읽어서 인덱스 구성
    final getRes = await api.spreadsheets.values.get(spreadsheetId, range);
    final existing = getRes.values ?? [];
    // key: yyyy-MM-dd|userId|status  -> rowNumber(2-based)
    final index = <String, int>{};
    for (int i = 0; i < existing.length; i++) {
      final r = existing[i];
      if (r.length < 7) continue;
      final dateStr = r[0].toString();
      final uid = r[2].toString();
      final st = r[6].toString();
      index['$dateStr|$uid|$st'] = i + 2; // 시트 행 번호(헤더 보정)
    }

    // 2) 업데이트 vs 새 추가 분리
    final List<ValueRange> updateRanges = [];
    final List<List<Object?>> appendValues = [];

    for (final e in rows) {
      final dateStr = DateFormat('yyyy-MM-dd').format(e.date);
      final key = '$dateStr|${e.userId}|${e.status}';
      final rowNum = index[key];

      if (rowNum != null) {
        // 기존 행: B열(시간)만 갱신
        updateRanges.add(
          ValueRange(
            range: '출퇴근기록!B$rowNum',
            values: [
              [e.time]
            ],
          ),
        );
      } else {
        // 신규 행: A~G 모두 한 줄 append
        appendValues.add(
          [dateStr, e.time, e.userId, e.userName, e.area, e.division, e.status],
        );
      }
    }

    // 3) 여러 셀 동시 갱신
    if (updateRanges.isNotEmpty) {
      await api.spreadsheets.values.batchUpdate(
        BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: updateRanges,
        ),
        spreadsheetId,
      );
    }

    // 4) 여러 행 동시 추가
    if (appendValues.isNotEmpty) {
      await api.spreadsheets.values.append(
        ValueRange(values: appendValues),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 배치 업서트 API (휴게)
  // ───────────────────────────────────────────────────────────────────────────
  static Future<void> upsertBreakBatchById({
    required String spreadsheetId,
    required List<BreakRow> rows,
  }) async {
    if (rows.isEmpty) return;

    final api = await _sheetsApi();
    const range = '휴게기록!A2:G';

    // 1) 현재 범위 한 번만 읽어서 인덱스 구성
    final getRes = await api.spreadsheets.values.get(spreadsheetId, range);
    final existing = getRes.values ?? [];
    // key: yyyy-MM-dd|userId|'휴게'  -> rowNumber(2-based)
    final index = <String, int>{};
    for (int i = 0; i < existing.length; i++) {
      final r = existing[i];
      if (r.length < 7) continue;
      final dateStr = r[0].toString();
      final uid = r[2].toString();
      final st = r[6].toString();
      index['$dateStr|$uid|$st'] = i + 2;
    }

    // 2) 업데이트 vs 새 추가 분리
    final List<ValueRange> updateRanges = [];
    final List<List<Object?>> appendValues = [];

    for (final e in rows) {
      final dateStr = DateFormat('yyyy-MM-dd').format(e.date);
      const status = '휴게';
      final key = '$dateStr|${e.userId}|$status';
      final rowNum = index[key];

      if (rowNum != null) {
        // 기존 행: B열(시간)만 갱신
        updateRanges.add(
          ValueRange(
            range: '휴게기록!B$rowNum',
            values: [
              [e.time]
            ],
          ),
        );
      } else {
        // 신규 행: A~G 모두 한 줄 append
        appendValues.add(
          [dateStr, e.time, e.userId, e.userName, e.area, e.division, status],
        );
      }
    }

    // 3) 여러 셀 동시 갱신
    if (updateRanges.isNotEmpty) {
      await api.spreadsheets.values.batchUpdate(
        BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: updateRanges,
        ),
        spreadsheetId,
      );
    }

    // 4) 여러 행 동시 추가
    if (appendValues.isNotEmpty) {
      await api.spreadsheets.values.append(
        ValueRange(values: appendValues),
        spreadsheetId,
        range,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
    }
  }
}
