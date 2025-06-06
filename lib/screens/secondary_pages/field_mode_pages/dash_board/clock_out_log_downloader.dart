import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// GCS에서 퇴근기록 JSON을 다운로드하여 파싱합니다.
/// 반환 형태: Map<userId_out, Map<dayIndex, time>>
Future<Map<String, Map<int, String>>?> downloadLeaveJsonFromGcs({
  required String publicUrl,
  required int selectedYear,
  required int selectedMonth,
}) async {
  try {
    final response = await http.get(Uri.parse(publicUrl));

    if (response.statusCode == 200) {
      debugPrint('📥 raw response.body: ${response.body}');
      final raw = jsonDecode(response.body);

      if (raw is! Map<String, dynamic>) {
        debugPrint('❌ JSON 구조가 Map이 아님');
        return null;
      }

      debugPrint('📥 decoded JSON map: $raw');

      final userId = raw['userId'] as String?;
      final time = raw['recordedTime'] as String?;
      final recordedDate = raw['recordedDate'] as String?;

      if (userId == null || time == null || recordedDate == null) {
        debugPrint('❌ 필수 필드 누락');
        return null;
      }

      final dateParts = recordedDate.split('-');
      if (dateParts.length != 3) {
        debugPrint('❌ recordedDate 형식 오류: $recordedDate');
        return null;
      }

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      if (year != selectedYear || month != selectedMonth) {
        debugPrint('📭 선택한 월과 업로드된 날짜가 일치하지 않음 → 무시됨');
        return null;
      }

      debugPrint('✅ 퇴근 기록 파싱 완료 → ${userId}_out [$day] = $time');

      return {
        '${userId}_out': {
          day: time,
        }
      };
    } else {
      debugPrint('❌ 서버 응답 오류: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('❌ JSON 다운로드 중 예외 발생: $e');
  }

  return null;
}
