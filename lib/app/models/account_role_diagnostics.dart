import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils/secure_auth_diagnostics.dart';

import '../../features/selector/application/dev_auth.dart';

class AccountRoleDiagnostics {
  AccountRoleDiagnostics._();

  static final List<String> _lines = <String>[];
  static final List<String> _accountCreationLines = <String>[];
  static final List<String> _accountListLines = <String>[];
  static final ValueNotifier<int> creationRevision = ValueNotifier<int>(0);
  static final ValueNotifier<int> listRevision = ValueNotifier<int>(0);

  static String get creationSummary => _accountCreationLines.isEmpty
      ? '계정 생성 진단: 기록 없음'
      : _accountCreationLines.reversed.take(3).toList().reversed.join('\n');

  static String get listSummary => _accountListLines.isEmpty
      ? '계정 목록 진단: 기록 없음'
      : _accountListLines.reversed.take(3).toList().reversed.join('\n');

  static void recordList(String event) {
    final safe = SecureAuthDiagnostics.redact(
      '[ACCOUNT_LIST][${DateTime.now().toIso8601String()}] $event',
    );
    debugPrint(safe);
    _accountListLines.add(safe);
    if (_accountListLines.length > 160) {
      _accountListLines.removeRange(0, _accountListLines.length - 160);
    }
    listRevision.value++;
  }

  static void record(String event) {
    if (!DevAuth.devModeEnabled.value) return;
    final line = '[ACCOUNT_ROLE][${DateTime.now().toIso8601String()}] $event';
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 160) {
      _lines.removeRange(0, _lines.length - 160);
    }
  }

  static void recordCreation(String event) {
    final safe = SecureAuthDiagnostics.redact(
      '[ACCOUNT_CREATE][${DateTime.now().toIso8601String()}] $event',
    );
    debugPrint(safe);
    _accountCreationLines.add(safe);
    creationRevision.value++;
    if (_accountCreationLines.length > 160) {
      _accountCreationLines.removeRange(0, _accountCreationLines.length - 160);
    }
  }

  static String get debugPrintCode => <String>[
    ..._accountCreationLines,
    ..._accountListLines,
    ..._lines,
  ].map((line) =>
      'debugPrint(${jsonEncode(SecureAuthDiagnostics.redact(line))});')
      .join('\n');
}
