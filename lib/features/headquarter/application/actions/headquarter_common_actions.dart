import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../attendance/application/attendance_diagnostics.dart';
import '../../../attendance/application/common_attendance_service.dart';
import '../../../dashboard/widgets/widgets/info/my_info_dialog.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../selector/application/dev_auth.dart';

class HeadquarterCommonActions {
  HeadquarterCommonActions._();

  static final List<String> _debugLines = <String>[];

  static List<String> get debugLines => List<String>.unmodifiable(
        <String>[...AttendanceDiagnostics.lines, ..._debugLines],
      );

  static String get debugPrintCode => <String>[
        ..._debugLines,
        ...AttendanceDiagnostics.lines,
      ].map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');

  static void recordEvent({
    required String source,
    required String action,
    required String phase,
    Map<String, Object?> meta = const <String, Object?>{},
  }) {
    final fields = <String>[
      'source=$source',
      'action=$action',
      'phase=$phase',
      ...meta.entries.map((entry) => '${entry.key}=${entry.value}'),
    ];
    final line =
        '[HQ_COMMON_ACTION][${DateTime.now().toIso8601String()}] ${fields.join(' ')}';
    _debugLines.add(line);
    if (_debugLines.length > 240) {
      _debugLines.removeRange(0, _debugLines.length - 240);
    }
    debugPrint(line);
  }

  static Future<T> run<T>({
    required String source,
    required String action,
    required Future<T> Function() operation,
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    recordEvent(
      source: source,
      action: action,
      phase: 'start',
      meta: meta,
    );
    try {
      final result = await operation();
      recordEvent(
        source: source,
        action: action,
        phase: 'complete',
        meta: meta,
      );
      return result;
    } catch (error, stackTrace) {
      recordEvent(
        source: source,
        action: action,
        phase: 'failure',
        meta: <String, Object?>{
          ...meta,
          'error': error,
        },
      );
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  static Future<void> openMyInfo(
    BuildContext context, {
    required String source,
  }) {
    return run<void>(
      source: source,
      action: 'open_my_info',
      operation: () => showMyInfoDialog(
        context: context,
        source: MyInfoEntrySource.hqDashboard,
      ),
    );
  }

  static Future<void> logout(
    BuildContext context, {
    required String source,
  }) {
    return run<void>(
      source: source,
      action: 'logout',
      operation: () => LogoutHelper.logoutAndGoToLogin(
        context,
        useCommonUi: true,
      ),
    );
  }

  static Future<void> recordBreak(
    BuildContext context, {
    required String source,
    Future<void> Function(DateTime recordedAt)? onRecorded,
  }) {
    return run<void>(
      source: source,
      action: 'record_break',
      meta: const <String, Object?>{
        'context': 'headquarter',
        'modeIndependent': true,
      },
      operation: () async {
        final trace = await DeveloperOperationTrace.start(
          context: context,
          title: '근태 처리 상태',
          initialMessage: '본사 휴게 기록을 시작합니다.',
          useCommonUi: true,
          developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
          standardModeMessage: '근태 처리를 진행합니다.',
          showDialogImmediately: false,
        );
        trace.log(
          'source=headquarter:$source action=record_break',
          progress: .12,
        );
        try {
          final result = await CommonAttendanceService.recordBreak(
            context,
            source: 'headquarter:$source',
            trace: trace,
          );
          final recordedAt = result.recordedAt;
          if (!result.success || recordedAt == null) {
            recordEvent(
              source: source,
              action: 'record_break',
              phase: 'record_failed',
              meta: <String, Object?>{
                'context': 'headquarter',
                'message': result.message,
              },
            );
            throw StateError(result.message);
          }
          recordEvent(
            source: source,
            action: 'record_break',
            phase: 'recorded',
            meta: <String, Object?>{
              'context': 'headquarter',
              'at': recordedAt.toIso8601String(),
              'message': result.message,
            },
          );
          trace.log(
            'attendance_result success=true message=${result.message}',
            progress: .82,
          );
          await trace.succeed(result.message);
          if (trace.developerMode && context.mounted) {
            await trace.showStatusDialog(context);
          }
          await onRecorded?.call(recordedAt);
        } catch (error, stackTrace) {
          await trace.fail(
            '휴게 기록에 실패했습니다.',
            error: error,
            stackTrace: stackTrace,
          );
          if (trace.developerMode && context.mounted) {
            await trace.showStatusDialog(context);
          }
          rethrow;
        }
      },
    );
  }

  static Future<void> clockOut(
    BuildContext context, {
    required String source,
    Future<void> Function(DateTime recordedAt)? onRecorded,
  }) {
    return run<void>(
      source: source,
      action: 'clock_out',
      meta: const <String, Object?>{
        'context': 'headquarter',
        'modeIndependent': true,
      },
      operation: () async {
        final trace = await DeveloperOperationTrace.start(
          context: context,
          title: '근태 처리 상태',
          initialMessage: '본사 퇴근 기록을 시작합니다.',
          useCommonUi: true,
          developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
          standardModeMessage: '근태 처리를 진행합니다.',
          showDialogImmediately: false,
        );
        trace.log(
          'source=headquarter:$source action=clock_out',
          progress: .12,
        );
        final result = await CommonAttendanceService.clockOut(
          context,
          source: 'headquarter:$source',
          trace: trace,
        );
        final recordedAt = result.recordedAt;
        if (!result.success || recordedAt == null) {
          await trace.fail(result.message);
          if (trace.developerMode && context.mounted) {
            await trace.showStatusDialog(context);
          }
          recordEvent(
            source: source,
            action: 'clock_out',
            phase: 'record_failed',
            meta: <String, Object?>{
              'context': 'headquarter',
              'message': result.message,
            },
          );
          throw StateError(result.message);
        }
        recordEvent(
          source: source,
          action: 'clock_out',
          phase: 'recorded',
          meta: <String, Object?>{
            'context': 'headquarter',
            'at': recordedAt.toIso8601String(),
            'message': result.message,
          },
        );
        trace.log(
          'attendance_result success=true message=${result.message}',
          progress: .82,
        );
        await trace.succeed(result.message);
        if (trace.developerMode && context.mounted) {
          await trace.showStatusDialog(context);
        }
        await onRecorded?.call(recordedAt);
        try {
          if (DebugActionRecorder.instance.isRecording) {
            await DebugActionRecorder.instance.stopAndSave(
              titleOverride: 'auto:clockout_exit',
            );
          }
        } catch (error, stackTrace) {
          recordEvent(
            source: source,
            action: 'clock_out',
            phase: 'debug_recorder_stop_failure',
            meta: <String, Object?>{'error': error},
          );
          debugPrint(stackTrace.toString());
        }
        if (!context.mounted) return;
        await AppExitService.exitApp(context, useCommonUi: true);
      },
    );
  }

  static Future<void> showDeveloperStatus(
    BuildContext context, {
    required String title,
    required String description,
    List<String> additionalLines = const <String>[],
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;
    HapticFeedback.mediumImpact();
    final lines = <String>[
      ...additionalLines,
      ...AttendanceDiagnostics.lines,
      ..._debugLines,
    ];
    final code = lines.isEmpty
        ? 'debugPrint(${jsonEncode('[HQ_COMMON_ACTION] 기록된 로그가 없습니다.')});'
        : lines
            .map((line) => 'debugPrint(${jsonEncode(line)});')
            .join('\n');
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: description,
      copyText: code,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
