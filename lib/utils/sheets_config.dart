// lib/utils/sheets_config.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 업로드(출근/퇴근/휴게)용 Google Sheets ID를 앱 설정에 저장/로드하는 유틸.
/// TimesheetPage에서 사용하는 hq_sheet_id와는 별도로 동작합니다.
class SheetsConfig {
  /// CommuteInsideScreen에서 설정하는 업로드용 공통 스프레드시트 ID
  static const String _commuteSheetIdKey = 'commute_sheet_id';

  /// 스프레드시트 URL 전체를 붙여넣어도 중간의 ID만 추출해주는 헬퍼
  /// 예) https://docs.google.com/spreadsheets/d/<ID>/edit → <ID>
  static String extractSpreadsheetId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(s);
    if (m != null) return m.group(1)!;
    return s; // 이미 ID만 들어온 경우
  }

  /// 업로드용 시트 ID 저장
  static Future<void> setCommuteSheetId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_commuteSheetIdKey, id.trim());
  }

  /// 업로드용 시트 ID 로드
  static Future<String?> getCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_commuteSheetIdKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  /// 업로드용 시트 ID 삭제(초기화)
  static Future<void> clearCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_commuteSheetIdKey);
  }
}
