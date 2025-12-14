// File: lib/utils/tts_local_log.dart
import 'package:flutter/foundation.dart';
import 'debug_local_logger.dart';

/// TTS 관련 '중요' 상황만 로컬 error 로그로 기록.
/// 같은 키(메시지/주요 컨텍스트)가 5초 안에 반복되면 억제(스팸 방지).
class TtsLocalLog {
  static DateTime? _lastAt;
  static String? _lastKey;

  static Future<void> error(String tag, String message, {Map<String, Object?>? data}) async {
    final key = '$tag|$message|${data?['id'] ?? ''}|${data?['area'] ?? ''}|${data?['type'] ?? ''}';
    final now = DateTime.now();
    if (_lastKey == key && _lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 5)) {
      return; // throttle duplicates within 5s
    }
    _lastKey = key;
    _lastAt = now;

    try {
      await DebugLocalLogger().log(
        {
          'tag': tag,
          'message': message,
          if (data != null) 'ctx': data, // context
        },
        level: 'error',
        tags: const ['tts'],
      );
    } catch (e) {
      debugPrint('❌ TtsLocalLog.error 실패: $e');
    }
  }
}
