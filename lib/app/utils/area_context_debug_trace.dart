import 'dart:convert';

import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';
import 'status_dialog.dart';

class AreaContextDebugTrace {
  static const int _limit = 320;
  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void record(
    String source,
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final cleanSource = source.trim();
    final cleanEvent = event.trim();
    if (cleanSource.isEmpty || cleanEvent.isEmpty) return;

    final payload = fields.isEmpty ? '' : ' ${jsonEncode(fields)}';
    final line =
        '[AreaContext][${DateTime.now().toIso8601String()}][$cleanSource] $cleanEvent$payload';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[AreaContext] recorded_logs_empty')});';
    }
    return _lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
  }

  static Future<void> showStatusDialog(
    BuildContext context, {
    bool useCommonUi = true,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;

    record('AreaContextDebugTrace', 'developer_status_requested');
    final description = _lines.isEmpty
        ? '[AreaContext] recorded_logs_empty'
        : _lines.join('\n');

    await StatusDialog.showSuccess(
      context,
      title: '지역 컨텍스트 개발자 상태',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: useCommonUi,
      awaitManualClose: true,
    );
  }
}
