import 'package:flutter/material.dart';
import '../../../../utils/google_sheets_helper.dart';

/// Google Sheets에서 출근기록을 가져와 파싱합니다.
/// 반환 형태: Map<userId, Map<dayIndex, time>>
Future<Map<String, Map<int, String>>?> downloadAttendanceJsonFromSheets({
  required int selectedYear,
  required int selectedMonth,
}) async {
  try {
    // ✅ Google Sheets에서 전체 출근기록 로드
    final rows = await GoogleSheetsHelper.loadClockInOutRecords();

    // ✅ 필요한 구조로 변환
    final result = GoogleSheetsHelper.mapToCellData(
      rows,
      statusFilter: '출근', // 출근 상태로 필터링
      selectedYear: selectedYear,
      selectedMonth: selectedMonth,
    );

    if (result.isEmpty) {
      debugPrint('📭 선택한 월의 출근기록 없음');
      return null;
    }

    debugPrint('✅ Google Sheets에서 출근기록 파싱 완료: ${result.length}명');
    return result;
  } catch (e) {
    debugPrint('❌ Google Sheets 출근기록 불러오기 실패: $e');
    return null;
  }
}
