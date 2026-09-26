import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';
import '../utils/status_dialog.dart';

class ThemeDebugTrace {
  ThemeDebugTrace._();

  static const int _maxLines = 320;
  static final List<String> _lines = <String>[];
  static bool _dialogShowing = false;

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void record(
    String event, {
    required String source,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final normalizedSource = source.trim().isEmpty ? 'unknown' : source.trim();
    final buffer = StringBuffer()
      ..write('[ThemeContext] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event)
      ..write(' source=')
      ..write(normalizedSource);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    debugPrint(line);
  }

  static String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  static Future<void> showStatusDialog(
    BuildContext context, {
    required String source,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    if (_dialogShowing || !context.mounted) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted || _dialogShowing) return;
    record(
      'developer_status_opened',
      source: source,
      details: <String, Object?>{
        ...details,
        'lineCount': _lines.length,
      },
    );
    final description = <String>[
      for (final entry in details.entries)
        '${entry.key}=${entry.value ?? '-'}',
      if (_lines.isNotEmpty) '',
      ..._lines,
    ].join('\n');
    final code = debugPrintCode.trim();
    if (code.isEmpty) return;
    _dialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: '테마 개발자 상태',
        description: description,
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
    } finally {
      _dialogShowing = false;
    }
  }
}
