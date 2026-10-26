import 'dart:convert';

import 'package:flutter/foundation.dart';

class AccessGateDiagnostics {
  AccessGateDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  static void record(
    String event, {
    required String source,
    String? group,
    String? reason,
  }) {
    final line = <String>[
      '[ACCESS_GATE]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'event=$event',
      'source=$source',
      if (group != null) 'group=$group',
      if (reason != null) 'reason=$reason',
    ].join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 200) {
      _lines.removeRange(0, _lines.length - 200);
    }
  }
}
