import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/utils/status_dialog.dart';
import '../../features/selector/application/dev_auth.dart';

class AccountCodeDiagnostics {
  static const int _maxLines = 160;
  static final List<_AccountCodeDiagnosticLine> _lines =
      <_AccountCodeDiagnosticLine>[];

  const AccountCodeDiagnostics._();

  static void record(
    String scope,
    String message, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final normalizedScope = scope.trim().isEmpty ? 'account-code' : scope.trim();
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) return;
    final payload = meta.isEmpty ? '' : ' ${jsonEncode(meta)}';
    final line =
        '[ACCOUNT-CODE][$normalizedScope][${DateTime.now().toIso8601String()}] $normalizedMessage$payload';
    _lines.add(
      _AccountCodeDiagnosticLine(
        scope: normalizedScope,
        line: line,
      ),
    );
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    debugPrint(line);
  }

  static String debugPrintCode({String? scope}) {
    final normalizedScope = scope?.trim();
    final selected = normalizedScope == null || normalizedScope.isEmpty
        ? _lines
        : _lines
            .where((entry) => entry.scope == normalizedScope)
            .toList(growable: false);
    if (selected.isEmpty) {
      return 'debugPrint(${jsonEncode('[ACCOUNT-CODE] 기록된 로그가 없습니다.')});';
    }
    return selected
        .map((entry) => 'debugPrint(${jsonEncode(entry.line)});')
        .join('\n');
  }

  static Future<void> showStatusDialog(
    BuildContext context, {
    required String scope,
    required String title,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: '코드번호 관련 debugPrint 기록입니다.',
      copyText: debugPrintCode(scope: scope),
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}

class _AccountCodeDiagnosticLine {
  const _AccountCodeDiagnosticLine({
    required this.scope,
    required this.line,
  });

  final String scope;
  final String line;
}
