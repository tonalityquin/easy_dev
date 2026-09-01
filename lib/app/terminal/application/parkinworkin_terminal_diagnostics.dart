import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../features/launcher/application/launcher_diagnostics.dart';
import '../../auth/gmail_sender_diagnostics.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../command/application/app_command_diagnostics.dart';
import '../../init/app_start_debug_trace.dart';
import '../../init/startup_tasks.dart';
import '../../utils/status_dialog.dart';

class ParkinWorkinTerminalDiagnostics {
  const ParkinWorkinTerminalDiagnostics._();

  static final List<String> _lines = <String>[];

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void record(
    String event, {
    required String context,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      '[PARKINWORKIN_TERMINAL]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'context=$context',
      'event=$event',
    ];
    for (final entry in meta.entries) {
      fields.add('${entry.key}=${entry.value}');
    }
    final line = fields.join(' ');
    debugPrint(line);
    _lines.add(line);
    if (_lines.length > 320) {
      _lines.removeRange(0, _lines.length - 320);
    }
  }

  static String get debugPrintCode {
    final merged = <String>[
      ...StartupTasks.debugLines,
      ...AppStartDebugTrace.lines,
      ...LauncherDiagnostics.lines,
      ...AppCommandDiagnostics.lines,
      ...GmailSenderDiagnostics.lines,
      ..._lines,
    ];
    if (merged.isEmpty) {
      return 'debugPrint(${jsonEncode('[PARKINWORKIN_TERMINAL] 기록된 로그가 없습니다.')});';
    }
    return merged
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String terminalContext,
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    record(
      'developer_status_open',
      context: terminalContext,
      meta: <String, Object?>{
        'terminalLines': _lines.length,
        'launcherLines': LauncherDiagnostics.lines.length,
        'commandLines': AppCommandDiagnostics.lines.length,
        'gmailSenderLines': GmailSenderDiagnostics.lines.length,
        'startupLines': StartupTasks.debugLines.length,
        'appStartLines': AppStartDebugTrace.lines.length,
      },
    );
    await StatusDialog.showSuccess(
      context,
      title: 'ParkinWorkin Terminal Status',
      description: description,
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
