import 'dart:convert';

import 'package:flutter/foundation.dart';

class LiveWorkDiagnostics {
  LiveWorkDiagnostics._();

  static const int maxLines = 240;
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void record(String event, [Map<String, Object?> values = const {}]) {
    final fields = values.entries
        .map((entry) => '${entry.key}=${entry.value ?? '-'}')
        .join(' ');
    final line =
        '[LIVE_WORK][${DateTime.now().toIso8601String()}] $event${fields.isEmpty ? '' : ' $fields'}';
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > maxLines) {
      _lines.removeRange(0, _lines.length - maxLines);
    }
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[LIVE_WORK] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }
}
