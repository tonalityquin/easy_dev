import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/auth/gmail_sender_diagnostics.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/startup_tasks.dart';
import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';
import '../../../shared/tts/application/plate_tts_session_diagnostics.dart';

class LauncherDiagnostics {
  const LauncherDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static String get debugPrintCode {
    final merged = <String>[
      ...StartupTasks.debugLines,
      ...AppStartDebugTrace.lines,
      ...GmailSenderDiagnostics.lines,
      ...PlateTtsSessionDiagnostics.lines,
      ..._lines,
    ];
    if (merged.isEmpty) {
      return 'debugPrint(${jsonEncode('[LAUNCHER] 기록된 로그가 없습니다.')});';
    }
    return merged
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void record(
    String event, {
    String scope = 'launcher',
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[LAUNCHER]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'scope=$scope',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 260) {
      _lines.removeRange(0, _lines.length - 260);
    }
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String title,
    required String description,
    String scope = 'launcher',
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    record(
      'developer_status_open',
      scope: scope,
      meta: <String, Object?>{
        'launcherLines': _lines.length,
        'startupLines': StartupTasks.debugLines.length,
        'appStartLines': AppStartDebugTrace.lines.length,
        'gmailSenderLines': GmailSenderDiagnostics.lines.length,
        'plateTtsSessionLines': PlateTtsSessionDiagnostics.lines.length,
      },
    );
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
