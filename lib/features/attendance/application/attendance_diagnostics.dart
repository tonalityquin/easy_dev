import 'dart:convert';

import 'package:flutter/foundation.dart';

class AttendanceDiagnostics {
  AttendanceDiagnostics._();

  static const int _limit = 320;
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[ATTENDANCE] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void record(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      'event=$event',
      ...meta.entries.map((entry) => '${entry.key}=${entry.value}'),
    ];
    final line =
        '[ATTENDANCE][${DateTime.now().toIso8601String()}] ${fields.join(' ')}';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }
}
