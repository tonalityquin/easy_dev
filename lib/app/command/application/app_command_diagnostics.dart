import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../features/selector/application/dev_auth.dart';
import '../../utils/status_dialog.dart';

class AppCommandDiagnostics {
  AppCommandDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  static void record({
    required String phase,
    required String input,
    required String normalized,
    String source = '',
    String command = '',
    String result = '',
    Object? error,
  }) {
    final fields = <String>[
      'phase=$phase',
      'input=${jsonEncode(input)}',
      'normalized=${jsonEncode(normalized)}',
      if (source.isNotEmpty) 'source=${jsonEncode(source)}',
      if (command.isNotEmpty) 'command=${jsonEncode(command)}',
      if (result.isNotEmpty) 'result=$result',
      if (error != null) 'error=${jsonEncode(error.toString())}',
    ];
    final line =
        '[APP_COMMAND][${DateTime.now().toIso8601String()}] ${fields.join(' ')}';
    _lines.add(line);
    if (_lines.length > 220) {
      _lines.removeRange(0, _lines.length - 220);
    }
    debugPrint(line);
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String title,
    required String description,
    bool failure = false,
  }) async {
    if (!context.mounted) return;
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;
    final code = debugPrintCode.trim();
    final copyText = code.isEmpty
        ? 'debugPrint(${jsonEncode('[APP_COMMAND] 기록된 로그가 없습니다.')});'
        : code;
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
