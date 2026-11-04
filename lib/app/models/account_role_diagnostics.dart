import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';

class AccountRoleDiagnostics {
  AccountRoleDiagnostics._();

  static final List<String> _lines = <String>[];

  static void record(String event) {
    if (!DevAuth.devModeEnabled.value) return;
    final line = '[ACCOUNT_ROLE][${DateTime.now().toIso8601String()}] $event';
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 160) {
      _lines.removeRange(0, _lines.length - 160);
    }
  }

  static String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');
}
