import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../dashboard/sheets/double/double_home_dash_board_controller.dart';
import '../../../dashboard/sheets/minor/minor_home_dash_board_controller.dart';
import '../../../dashboard/sheets/single/single_home_dash_board_controller.dart';
import '../../../dashboard/sheets/triple/triple_home_dash_board_controller.dart';
import '../../../dashboard/widgets/widgets/info/my_info_dialog.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../mode_single/application/att_brk_repository.dart';
import '../../../selector/application/dev_auth.dart';
import '../../../selector/sheets/service_bottom_sheet.dart';
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

  static Future<void> openSettings(
    BuildContext context, {
    required String source,
  }) {
    return run<void>(
      source: source,
      action: 'open_service_settings',
      operation: () async {
        final rootContext = Navigator.of(
          context,
          rootNavigator: true,
        ).context;
        await ServiceBottomSheet.show(context: rootContext);
      },
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

  static Future<void> openWorkActions(
    BuildContext context, {
    required String source,
    String? modeKey,
  }) {
    final resolvedMode = currentModeKey(fallback: modeKey);
    return run<void>(
      source: source,
      action: 'open_work_actions',
      meta: <String, Object?>{'mode': resolvedMode},
      operation: () => showCommonDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => _HeadquarterWorkActionsDialog(
          parentContext: context,
          source: source,
          modeKey: resolvedMode,
        ),
      ),
    );
  }

  static Future<void> recordBreak(
    BuildContext context, {
    required String source,
    required String modeKey,
  }) {
    final resolvedMode = currentModeKey(fallback: modeKey);
    return run<void>(
      source: source,
      action: 'record_break',
      meta: <String, Object?>{'mode': resolvedMode},
      operation: () async {
        switch (resolvedMode) {
          case 'double':
            await _doubleController.recordBreakTime(context);
            return;
          case 'triple':
            await _tripleController.recordBreakTime(context);
            return;
          case 'minor':
            await _minorController.recordBreakTime(context);
            return;
          case 'single':
          default:
            await _singleController.recordBreakTime(context);
            return;
        }
      },
    );
  }

  static Future<void> clockOut(
    BuildContext context, {
    required String source,
    required String modeKey,
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

class _HeadquarterWorkActionsDialog extends StatefulWidget {
  const _HeadquarterWorkActionsDialog({
    required this.parentContext,
    required this.source,
    required this.modeKey,
  });

  final BuildContext parentContext;
  final String source;
  final String modeKey;

  @override
  State<_HeadquarterWorkActionsDialog> createState() =>
      _HeadquarterWorkActionsDialogState();
}

class _HeadquarterWorkActionsDialogState
    extends State<_HeadquarterWorkActionsDialog> {
  bool _breakSubmitting = false;
  bool _clockOutSubmitting = false;

  Future<void> _recordBreak() async {
    if (_breakSubmitting || _clockOutSubmitting) return;
    setState(() => _breakSubmitting = true);
    try {
      await HeadquarterCommonActions.recordBreak(
        widget.parentContext,
        source: widget.source,
        modeKey: widget.modeKey,
      );
    } finally {
      if (mounted) setState(() => _breakSubmitting = false);
    }
  }

  Future<void> _clockOut() async {
    if (_breakSubmitting || _clockOutSubmitting) return;
    setState(() => _clockOutSubmitting = true);
    final parentContext = widget.parentContext;
    final source = widget.source;
    final modeKey = widget.modeKey;
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!parentContext.mounted) return;
    await HeadquarterCommonActions.clockOut(
      parentContext,
      source: source,
      modeKey: modeKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final busy = _breakSubmitting || _clockOutSubmitting;

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
      curve: CommonUiMotion.standard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.infoContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.work_history_rounded,
                  color: tokens.onInfoContainer,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '근무 액션',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              CommonIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                haptic: CommonHaptic.selection,
              ),
            ],
          ),
          const SizedBox(height: 14),
          CommonButton(
            label: '휴게 사용 확인',
            icon: Icons.coffee_rounded,
            onPressed: busy ? null : _recordBreak,
            loading: _breakSubmitting,
            expand: true,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.light,
            semanticsLabel: '휴게 사용 확인',
          ),
          const SizedBox(height: 8),
          CommonButton(
            label: '퇴근하기',
            icon: Icons.exit_to_app_rounded,
            onPressed: busy ? null : _clockOut,
            loading: _clockOutSubmitting,
            expand: true,
            variant: CommonButtonVariant.destructive,
            haptic: CommonHaptic.medium,
            semanticsLabel: '퇴근하기',
          ),
        ],
      ),
    );
  }
}
