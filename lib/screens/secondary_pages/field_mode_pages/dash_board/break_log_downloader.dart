import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// GCS에서 휴게시간 JSON을 다운로드하여 파싱합니다.
/// 반환 형태: Map<userId, Map<dayIndex, time>>
Future<Map<String, Map<int, String>>?> downloadBreakJsonFromGcs({
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
      // ✅ 한글 깨짐 방지를 위해 utf8 디코딩
      final decodedContent = utf8.decode(response.bodyBytes);
      debugPrint('📥 휴게 로그 원본: $decodedContent');

      final decoded = jsonDecode(decodedContent);

      if (decoded is! List) {
        debugPrint('❌ JSON은 List<Map> 형식이어야 합니다.');
        return null;
      }

      final Map<String, Map<int, String>> parsed = {};

      for (final entry in decoded) {
        if (entry is! Map) continue;

        final userId = entry['userId'] as String?;
        final recordedDate = entry['recordedDate'] as String?;
        final recordedTime = entry['recordedTime'] as String?;

        if (userId == null || recordedDate == null || recordedTime == null) continue;

        final parts = recordedDate.split('-');
        if (parts.length != 3) continue;

        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        final day = int.tryParse(parts[2]);
        if (year == null || month == null || day == null) continue;

        if (year != selectedYear || month != selectedMonth) {
          debugPrint('📭 $recordedDate → 선택한 연월과 불일치 → 무시됨');
          continue;
        }

        parsed.putIfAbsent(userId, () => {})[day] = recordedTime;
      }

      debugPrint('✅ 휴게 로그 파싱 결과: $parsed');
      return parsed;
    } else {
      debugPrint('❌ HTTP 오류: ${response.statusCode}');
    }
  } catch (e) {
    debugPrint('❌ 예외 발생: $e');
  }

  return null;
}
