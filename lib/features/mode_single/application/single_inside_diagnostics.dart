import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../launcher/application/launcher_diagnostics.dart';
import '../../selector/application/dev_auth.dart';

class SingleInsideDiagnostics {
  SingleInsideDiagnostics._();

  static const int _limit = 360;
  static final List<String> _lines = <String>[];

  static void log(String scope, String message) {
    final normalizedScope = scope.trim().isEmpty ? 'general' : scope.trim();
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) return;
    final line =
        '[SINGLE][$normalizedScope][${DateTime.now().toIso8601String()}] $normalizedMessage';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    final merged = <String>[
      ...LauncherDiagnostics.lines,
      ..._lines,
    ];
    if (merged.isEmpty) {
      return 'debugPrint(${jsonEncode('[SINGLE] 기록된 로그가 없습니다.')});';
    }
    return merged
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    String title = 'Single 상태',
    String description = 'Single UI 및 SQLite 공간 상태 로그',
    bool failure = false,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    log('status', 'open title=$title failure=$failure lines=${_lines.length}');
    final copyText = debugPrintCode;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: title,
        description: description,
        copyText: copyText,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
      return;
    }
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: description,
      copyText: copyText,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
