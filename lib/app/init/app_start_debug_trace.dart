import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/selector/application/dev_auth.dart';
import '../utils/status_dialog.dart';

class AppStartDebugTrace {
  const AppStartDebugTrace._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void log(
    String scope,
    String event, {
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final parts = <String>[
      '[APP_START]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'scope=$scope',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      parts.add('${entry.key}=${entry.value}');
    }
    final line = parts.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 240) {
      _lines.removeRange(0, _lines.length - 240);
    }
  }

  static Future<void> showDeveloperStatus(
    BuildContext context, {
    required String title,
    required String description,
    required String scope,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;

    log(
      scope,
      'developer_status_open',
      meta: <String, Object?>{'lines': _lines.length},
    );

    await HapticFeedback.mediumImpact();
    if (!context.mounted) return;

    await StatusDialog.showSuccess(
      context,
      title: title,
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 복사',
      visibleDuration: const Duration(seconds: 30),
      useCommonUi: true,
    );
  }
}
