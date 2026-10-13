import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../selector/application/dev_auth.dart';

class PersonalAccountDiagnostics {
  const PersonalAccountDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
  }

  static void record(
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[PERSONAL_ACCOUNT]',
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
      return 'debugPrint(${jsonEncode('[PERSONAL_ACCOUNT] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatusDialog(
    BuildContext context, {
    required String title,
    required String description,
    bool failure = false,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: title,
        description: description,
        copyText: debugPrintCode,
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
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
