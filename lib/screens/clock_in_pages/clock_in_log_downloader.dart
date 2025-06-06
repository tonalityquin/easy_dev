import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// GCS에서 출근기록 JSON을 다운로드하여 파싱합니다.
/// 반환 형태: Map<userId, Map<dayIndex, time>>
Future<Map<String, Map<int, String>>?> downloadAttendanceJsonFromGcs({
  required String publicUrl,
  required int selectedYear,
  required int selectedMonth,
}) async {
  try {
    // ✅ CDN 캐시 우회를 위한 쿼리 추가
    final uri = Uri.parse(publicUrl);
    final cacheBypassUrl = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'nocache': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final response = await http.get(cacheBypassUrl);

    if (response.statusCode == 200) {
      debugPrint('📥 raw response.body: ${response.body}');

      final raw = jsonDecode(response.body);

      if (raw is! Map<String, dynamic>) {
        debugPrint('❌ JSON 구조가 Map이 아님');
        return null;
      }

      debugPrint('📥 decoded JSON map: $raw');
      debugPrint('📥 available keys: ${raw.keys.join(', ')}');

      final userId = raw['userId'] as String?;
      final time = raw['recordedTime'] as String?;
      final recordedDate = raw['recordedDate'] as String?;

      debugPrint('📥 userId=$userId, recordedDate=$recordedDate, recordedTime=$time');
      debugPrint('📥 raw.keys: ${raw.keys.map((k) => "'$k'").toList()}');

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

      // ✅ 현재 선택된 연월과 JSON에 저장된 날짜가 일치해야 반영
      if (year != selectedYear || month != selectedMonth) {
        debugPrint('📭 선택한 월과 업로드된 날짜가 일치하지 않음 → 무시됨');
        return null;
      }

      debugPrint('✅ 출근 기록 파싱 완료 → $userId [$day] = $time');

      return {
        userId: {
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
