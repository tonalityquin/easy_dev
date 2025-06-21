import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// GCS에서 퇴근기록 JSON을 다운로드하여 파싱합니다.
/// JSON은 List<Map> 형식 (append 구조)
/// 반환 형태: Map<userId_out, Map<dayIndex, time>>
Future<Map<String, Map<int, String>>?> downloadLeaveJsonFromGcs({
  required String publicUrl,
  required int selectedYear,
  required int selectedMonth,
}) async {
  try {
    final uri = Uri.parse(publicUrl);
    final cacheBypassUrl = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'nocache': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final response = await http.get(
      cacheBypassUrl,
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
    );

    if (response.statusCode == 200) {
      debugPrint('📥 raw response.body: ${response.body}');
      final raw = jsonDecode(response.body);

      // ✅ append 구조 (List<Map>)
      if (raw is List) {
        final result = <String, Map<int, String>>{};

        for (final record in raw) {
          if (record is! Map<String, dynamic>) continue;

          final userId = record['userId'] as String?;
          final time = record['recordedTime'] as String?;
          final recordedDate = record['recordedDate'] as String?;

          if (userId == null || time == null || recordedDate == null) continue;

          final dateParts = recordedDate.split('-');
          if (dateParts.length != 3) continue;

          final year = int.tryParse(dateParts[0]);
          final month = int.tryParse(dateParts[1]);
          final day = int.tryParse(dateParts[2]);

          if (year == null || month == null || day == null) continue;

          if (year != selectedYear || month != selectedMonth) continue;

          final key = '${userId}_out';
          result.putIfAbsent(key, () => {})[day] = time;
        }

        if (result.isEmpty) {
          debugPrint('📭 선택한 월에 해당하는 퇴근 데이터 없음');
          return null;
        }

        debugPrint('✅ 퇴근 기록 리스트 파싱 완료: ${result.length}명');
        return result;
      }

      // ✅ 단일 기록 구조도 지원 (기존 호환성)
      if (raw is Map<String, dynamic>) {
        final userId = raw['userId'] as String?;
        final time = raw['recordedTime'] as String?;
        final recordedDate = raw['recordedDate'] as String?;

        if (userId == null || time == null || recordedDate == null) {
          debugPrint('❌ 단일 JSON 필수 필드 누락');
          return null;
        }

        final dateParts = recordedDate.split('-');
        if (dateParts.length != 3) return null;

        final year = int.tryParse(dateParts[0]);
        final month = int.tryParse(dateParts[1]);
        final day = int.tryParse(dateParts[2]);

        if (year == selectedYear && month == selectedMonth && day != null) {
          return {
            '${userId}_out': {
              day: time,
            }
          };
        } else {
          return null;
        }
      }

      debugPrint('❌ 알 수 없는 JSON 형식');
    } else {
      debugPrint('❌ 서버 응답 오류: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('❌ 퇴근 JSON 다운로드 중 예외 발생: $e');
  }

  return null;
}
