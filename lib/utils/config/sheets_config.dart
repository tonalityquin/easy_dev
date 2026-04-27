
import 'package:shared_preferences/shared_preferences.dart';




class SheetsConfig {
  
  static const String _commuteSheetIdKey = 'commute_sheet_id';

  
  static const String _endReportSheetIdKey = 'end_report_sheet_id';

  
  
  static String extractSpreadsheetId(String input) {
    final s = input.trim();
    final m = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)').firstMatch(s);
    if (m != null) return m.group(1)!;
    return s; 
  }

  

  
  static Future<void> setCommuteSheetId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_commuteSheetIdKey, id.trim());
  }

  
  static Future<String?> getCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_commuteSheetIdKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  
  static Future<void> clearCommuteSheetId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_commuteSheetIdKey);
  }

  

  
  static Future<void> setEndReportSheetId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_endReportSheetIdKey, id.trim());
  }

  
  static Future<String?> getEndReportSheetId() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_endReportSheetIdKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  
  static Future<void> clearEndReportSheetId() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_endReportSheetIdKey);
  }
}
