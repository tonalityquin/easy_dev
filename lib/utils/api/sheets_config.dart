// lib/utils/sheets_config.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Google Sheets ID를 앱 설정에 저장/로드하는 유틸.
/// - Commute(출퇴근 업로드) 용: commute_sheet_id
/// - EndWorkReport(업무 종료 보고 업로드) 용: end_report_sheet_id
class SheetsConfig {
  /// CommuteInsideScreen 업로드용 공통 스프레드시트 ID
  static const String _commuteSheetIdKey = 'commute_sheet_id';

  /// 업무 종료 보고 업로드용 스프레드시트 ID
  static const String _endReportSheetIdKey = 'end_report_sheet_id';

  /// 스프레드시트 URL 전체를 붙여넣어도 중간의 ID만 추출해주는 헬퍼
  /// 예) https://docs.google.com/spreadsheets/d/<ID>/edit → <ID>
  static String extractSpreadsheetId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(s);
    if (m != null) return m.group(1)!;
    return s; // 이미 ID만 들어온 경우
  }

  // ===================== Commute용 =====================

  /// 출퇴근 업로드용 시트 ID 저장
  static Future<void> setCommuteSheetId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_commuteSheetIdKey, id.trim());
  }

  /// 출퇴근 업로드용 시트 ID 로드
  static Future<String?> getCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_commuteSheetIdKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  /// 출퇴근 업로드용 시트 ID 삭제(초기화)
  static Future<void> clearCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_commuteSheetIdKey);
  }

  // ===================== EndWorkReport용 =====================

  /// 업무 종료 보고 업로드용 시트 ID 저장
  static Future<void> setEndReportSheetId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_endReportSheetIdKey, id.trim());
  }

  /// 업무 종료 보고 업로드용 시트 ID 로드
  static Future<String?> getEndReportSheetId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_endReportSheetIdKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  /// 업무 종료 보고 업로드용 시트 ID 삭제(초기화)
  static Future<void> clearEndReportSheetId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_endReportSheetIdKey);
  }
}
