import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';

class TabletDebugTrace {
  TabletDebugTrace._();

  static const int _maxLines = 240;
  static final List<String> _lines = <String>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static bool _dialogShowing = false;

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
    revision.value++;
  }

  static void record(
    String source,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[$source] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      final value = entry.value;
      if (value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(value);
    }
    final line = buffer.toString();
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    revision.value++;
    debugPrint(line);
  }

  static String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  static Future<void> showStatusDialog(
    BuildContext context, {
    String title = '태블릿 개발자 상태',
  }) async {
    if (_dialogShowing || !context.mounted || _lines.isEmpty) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted || _dialogShowing) return;
    final code = debugPrintCode.trim();
    if (code.isEmpty) return;
    _dialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: title,
        description: _lines.join('\n'),
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
