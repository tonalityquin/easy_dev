import 'dart:convert';

import 'package:flutter/foundation.dart';

class TabletAccountDiagnostics {
  const TabletAccountDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void record(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[TABLET_ACCOUNT]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 240) {
      _lines.removeRange(0, _lines.length - 240);
    }
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[TABLET_ACCOUNT] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }
}
