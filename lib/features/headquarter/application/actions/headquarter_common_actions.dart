import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../account/applications/user_state.dart';
import '../../../dashboard/applications/common/break_record_result.dart';
import '../../../dashboard/sheets/double/double_home_dash_board_controller.dart';
import '../../../dashboard/sheets/minor/minor_home_dash_board_controller.dart';
import '../../../dashboard/sheets/single/single_home_dash_board_controller.dart';
import '../../../dashboard/sheets/triple/triple_home_dash_board_controller.dart';
import '../../../dashboard/widgets/widgets/info/my_info_dialog.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../headquarter_dashboard_context.dart';

class HeadquarterCommonActions {
  HeadquarterCommonActions._();

  static final SingleHomeDashBoardController _singleController =
      SingleHomeDashBoardController();
  static final DoubleHomeDashBoardController _doubleController =
      DoubleHomeDashBoardController();
  static final TripleHomeDashBoardController _tripleController =
      TripleHomeDashBoardController();
  static final MinorHomeDashBoardController _minorController =
      MinorHomeDashBoardController();
  static final List<String> _debugLines = <String>[];

  static List<String> get debugLines => List<String>.unmodifiable(_debugLines);

  static String get debugPrintCode => _debugLines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  static String currentModeKey({String? fallback}) {
    final published = HeadquarterDashboardContext.normalizeModeKey(
      HeadquarterDashboardContext.currentModeKey.value,
    );
    if (published.isNotEmpty) return published;
    return HeadquarterDashboardContext.normalizeModeKey(fallback ?? '');
  }

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
    required String modeKey,
    Future<void> Function(DateTime recordedAt)? onRecorded,
  }) {
    final resolvedMode = currentModeKey(fallback: modeKey);
    return run<void>(
      source: source,
      action: 'record_break',
      meta: <String, Object?>{'mode': resolvedMode},
      operation: () async {
        late final BreakRecordResult result;
        switch (resolvedMode) {
          case 'double':
            result = await _doubleController.recordBreakTime(context);
            break;
          case 'triple':
            result = await _tripleController.recordBreakTime(context);
            break;
          case 'minor':
            result = await _minorController.recordBreakTime(context);
            break;
          case 'single':
          default:
            result = await _singleController.recordBreakTime(context);
            break;
        }
        final recordedAt = result.recordedAt;
        if (!result.success || recordedAt == null) {
          recordEvent(
            source: source,
            action: 'record_break',
            phase: 'record_failed',
            meta: <String, Object?>{
              'mode': resolvedMode,
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
            'mode': resolvedMode,
            'at': recordedAt.toIso8601String(),
            'message': result.message,
          },
        );
        await onRecorded?.call(recordedAt);
      },
    );
  }

  static Future<void> clockOut(
    BuildContext context, {
    required String source,
    required String modeKey,
    Future<void> Function(DateTime recordedAt)? onRecorded,
  }) {
    final resolvedMode = currentModeKey(fallback: modeKey);
    return run<void>(
      source: source,
      action: 'clock_out',
      meta: <String, Object?>{'mode': resolvedMode},
      operation: () async {
        final userState = context.read<UserState>();
        recordEvent(
          source: source,
          action: 'clock_out',
          phase: 'work_status_before',
          meta: <String, Object?>{
            'mode': resolvedMode,
            'isWorking': userState.isWorking,
          },
        );
        await _handleWorkStatus(resolvedMode, userState, context);
        if (!context.mounted) return;
        recordEvent(
          source: source,
          action: 'clock_out',
          phase: 'work_status_after',
          meta: <String, Object?>{
            'mode': resolvedMode,
            'isWorking': userState.isWorking,
          },
        );
        if (userState.isWorking) return;
        final session = userState.session;
        if (session != null) {
          final now = DateTime.now();
          await AttBrkRepository.instance.insertEventAndUpload(
            dateTime: now,
            type: AttBrkModeType.workOut,
            userId: session.id,
            userName: session.displayName,
            area: userState.currentArea,
            division: userState.division,
          );
          recordEvent(
            source: source,
            action: 'clock_out',
            phase: 'workout_event_recorded',
            meta: <String, Object?>{
              'mode': resolvedMode,
              'area': userState.currentArea,
              'division': userState.division,
              'at': now.toIso8601String(),
            },
          );
          await onRecorded?.call(now);
        }
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
    final lines = <String>[...additionalLines, ..._debugLines];
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

  static Future<void> _handleWorkStatus(
    String modeKey,
    UserState userState,
    BuildContext context,
  ) async {
    switch (modeKey) {
      case 'double':
        await _doubleController.handleWorkStatus(userState, context);
        return;
      case 'triple':
        await _tripleController.handleWorkStatus(userState, context);
        return;
      case 'minor':
        await _minorController.handleWorkStatus(userState, context);
        return;
      case 'single':
      default:
        await _singleController.handleWorkStatus(userState, context);
        return;
    }
  }
}
