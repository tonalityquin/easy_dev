import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';

class LoginDebugTrace {
  const LoginDebugTrace._();

  static const int _maxLinesPerScope = 240;
  static final Map<String, List<String>> _linesByScope =
      <String, List<String>>{};

  static void log(String scope, Object? message) {
    final normalizedScope = scope.trim().isEmpty ? 'login' : scope.trim();
    final normalizedMessage = message?.toString().trim() ?? '';
    if (normalizedMessage.isEmpty) return;
    final lines = _linesByScope.putIfAbsent(
      normalizedScope,
      () => <String>[],
    );
    lines.add(normalizedMessage);
    if (lines.length > _maxLinesPerScope) {
      lines.removeRange(0, lines.length - _maxLinesPerScope);
    }
    debugPrint(normalizedMessage);
  }

  static String debugPrintCode(String scope) {
    final normalizedScope = scope.trim().isEmpty ? 'login' : scope.trim();
    final lines = _linesByScope[normalizedScope] ?? const <String>[];
    if (lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[LOGIN][$normalizedScope] 기록된 로그가 없습니다.')});';
    }
    return lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatusDialog(
    BuildContext context, {
    required String scope,
    required String title,
    String additionalDebugPrintCode = '',
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    final primary = debugPrintCode(scope).trim();
    final additional = additionalDebugPrintCode.trim();
    final copyText = additional.isEmpty
        ? primary
        : '$primary\n$additional';
    await StatusDialog.showSuccess(
      context,
      title: title,
      copyText: copyText,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
