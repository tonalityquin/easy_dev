import 'dart:convert';

import '../../diagnostics/firebase_activity_meter.dart';
import '../../diagnostics/firebase_auth_rules_diagnostics.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../utils/build_optimization_diagnostics.dart';
import '../../utils/motion_timing_diagnostics.dart';
import '../../../features/account/applications/tablet_account_diagnostics.dart';
import '../../../features/launcher/application/launcher_diagnostics.dart';
import '../../auth/gmail_sender_diagnostics.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../../shared/area_remote_settings/application/area_snapshot_persistence.dart';
import '../../command/application/app_command_diagnostics.dart';
import '../../init/app_start_debug_trace.dart';
import '../../init/startup_tasks.dart';
import '../../init/work_status_notification.dart';
import '../../theme/theme_debug_trace.dart';
import '../../utils/status_dialog.dart';
import '../../models/account_role_diagnostics.dart';
import '../../utils/secure_auth_diagnostics.dart';

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
      ...WorkStatusNotificationController.debugLines,
      ...AppStartDebugTrace.lines,
      ...LauncherDiagnostics.lines,
      ...SecureAuthDiagnostics.lines,
      ...TabletAccountDiagnostics.lines,
      ...AppCommandDiagnostics.lines,
      ...GmailSenderDiagnostics.lines,
      ...AreaSnapshotPersistence.debugLines,
      ...ThemeDebugTrace.lines,
      ...MotionTimingDiagnostics.lines,
      ...BuildOptimizationDiagnostics.lines,
      ...StatusDialog.debugLines,
      ...FirebaseAuthRulesDiagnostics.lines,
      ...FirebaseActivityMeter.instance.events.reversed.map((event) => event.line),
      ..._lines,
    ];
    if (merged.isEmpty) {
      final roleCode = AccountRoleDiagnostics.debugPrintCode;
      return roleCode.isNotEmpty
          ? roleCode
          : 'debugPrint(${jsonEncode('[PARKINWORKIN_TERMINAL] 기록된 로그가 없습니다.')});';
    }
    final ordinary = merged
        .map((line) =>
            'debugPrint(${jsonEncode(SecureAuthDiagnostics.redact(line))});')
        .join('\n');
    return <String>[ordinary, AccountRoleDiagnostics.debugPrintCode]
        .where((part) => part.isNotEmpty)
        .join('\n');
  }

  static Future<String> debugPrintCodeWithJournal() async {
    if (!DevAuth.devModeEnabled.value ||
        !await DevAuth.isDevModeEnabled()) return '';
    await FirebaseAuthRulesDiagnostics.inspect(source: 'terminal_status_copy');
    final merged = <String>[
      ...StartupTasks.debugLines,
      ...WorkStatusNotificationController.debugLines,
      ...AppStartDebugTrace.lines,
      ...LauncherDiagnostics.lines,
      ...SecureAuthDiagnostics.lines,
      ...TabletAccountDiagnostics.lines,
      ...AppCommandDiagnostics.lines,
      ...GmailSenderDiagnostics.lines,
      ...AreaSnapshotPersistence.debugLines,
      ...ThemeDebugTrace.lines,
      ...MotionTimingDiagnostics.lines,
      ...BuildOptimizationDiagnostics.lines,
      ...StatusDialog.debugLines,
      ...FirebaseAuthRulesDiagnostics.lines,
      ..._lines,
    ];
    final ordinary = merged
        .map((line) =>
            'debugPrint(${jsonEncode(SecureAuthDiagnostics.redact(line))});')
        .join('\n');
    final activity = await FirebaseActivityMeter.instance.exportJournalCode();
    return <String>[
      ordinary,
      AccountRoleDiagnostics.debugPrintCode,
      activity,
    ].where((part) => part.isNotEmpty).join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    required String terminalContext,
    required String description,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    await BuildOptimizationDiagnostics.refresh(source: 'terminal_status');
    final authSnapshot = await FirebaseAuthRulesDiagnostics.inspect(
      source: 'terminal_status_open',
    );
    if (!context.mounted || !DevAuth.devModeEnabled.value) return;
    record(
      'developer_status_open',
      context: terminalContext,
      meta: <String, Object?>{
        'terminalLines': _lines.length,
        'launcherLines': LauncherDiagnostics.lines.length,
        'tabletAccountLines': TabletAccountDiagnostics.lines.length,
        'commandLines': AppCommandDiagnostics.lines.length,
        'gmailSenderLines': GmailSenderDiagnostics.lines.length,
        'areaSnapshotLines': AreaSnapshotPersistence.debugLines.length,
        'themeLines': ThemeDebugTrace.lines.length,
        'startupLines': StartupTasks.debugLines.length,
        'workStatusNotificationLines':
            WorkStatusNotificationController.debugLines.length,
        'appStartLines': AppStartDebugTrace.lines.length,
        'motionTimingLines': MotionTimingDiagnostics.lines.length,
        'buildOptimizationLines': BuildOptimizationDiagnostics.lines.length,
        'statusDialogLines': StatusDialog.debugLines.length,
      },
    );
    await StatusDialog.showSuccess(
      context,
      title: 'ParkinWorkin Terminal Status',
      description: description,
      securitySummary: '${authSnapshot.summary}\n'
          '${FirebaseActivityMeter.instance.rulesAuditSummary}\n'
          '${AccountRoleDiagnostics.creationSummary}\n'
          '${AccountRoleDiagnostics.listSummary}',
      securitySummaryChanges: Listenable.merge(<Listenable>[
        FirebaseActivityMeter.instance.summary,
        FirebaseAuthRulesDiagnostics.revision,
        AccountRoleDiagnostics.creationRevision,
        AccountRoleDiagnostics.listRevision,
      ]),
      securitySummaryProvider: () =>
          "${FirebaseAuthRulesDiagnostics.current?.summary ?? '인증 상태: 확인되지 않음'}\n"
          '${FirebaseActivityMeter.instance.rulesAuditSummary}\n'
          '${AccountRoleDiagnostics.creationSummary}\n'
          '${AccountRoleDiagnostics.listSummary}',
      copyText: debugPrintCode,
      copyTextProvider: debugPrintCodeWithJournal,
      requireDeveloperModeForCopy: true,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
