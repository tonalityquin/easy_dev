import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/init/missing_weekday_end_time_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../attendance/application/common_attendance_service.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../launcher/application/launcher_diagnostics.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/commute_pre_clock_in_gate.dart';
import '../../controllers/common_commute_in_controller.dart';
import '../../utils/commute_mode_spec.dart';
import '../../widgets/commute_destination_cinematic_entry.dart';
import '../widgets/commute_clock_in_issue_panel.dart';
import '../widgets/commute_end_time_setup_panel.dart';
import '../widgets/commute_pre_clock_in_checklist.dart';
import '../widgets/parkinworkin_windows_desktop.dart';

enum _CommutePowerGateStage {
  checking,
  ready,
  processing,
  success,
  failure,
}

enum _CommuteGateView {
  power,
  checklist,
}

class CommonCommuteInScreen extends StatefulWidget {
  const CommonCommuteInScreen({
    super.key,
    required this.spec,
    this.preClockInGate,
  });

  final CommuteModeSpec spec;
  final CommutePreClockInGate? preClockInGate;

  @override
  State<CommonCommuteInScreen> createState() => _CommonCommuteInScreenState();
}

class _CommonCommuteInScreenState extends State<CommonCommuteInScreen>
    with SingleTickerProviderStateMixin {
  late final CommonCommuteInController controller =
      CommonCommuteInController(spec: widget.spec);
  late final AnimationController _revealController;
  final GlobalKey<ParkinWorkinApplicationFieldState> _desktopKey =
      GlobalKey<ParkinWorkinApplicationFieldState>();
  _CommutePowerGateStage _stage = _CommutePowerGateStage.checking;
  String _stateMessage = '';
  static const Duration _menuMotionDuration = Duration(milliseconds: 180);
  static const Duration _preClockInChecklistMotionDuration =
      Duration(milliseconds: 360);

  bool _routeTransitioning = false;
  bool _showClockInIssueResolution = false;
  bool _resolvingClockInIssue = false;
  CommuteClockInIssueState? _clockInIssueState;
  String _clockInIssueFailureReason = '';
  String _clockInIssueFailureDetail = '';
  MissingWeekdayEndTimeRequirement? _endTimeRequirement;
  CommuteEndTimeSetupFeedback _endTimeFeedback =
      CommuteEndTimeSetupFeedback.editing;
  TimeOfDay _endTimeDraft = const TimeOfDay(hour: 0, minute: 0);
  CommuteEndTimeInputSource _endTimeInputSource =
      CommuteEndTimeInputSource.initial;
  bool _endTimeInputValid = true;
  String _endTimeInputText = '00:00';
  String _endTimeHourInput = '00';
  String _endTimeMinuteInput = '00';
  CommuteEndTimeInputField _endTimeFocusedField =
      CommuteEndTimeInputField.none;
  bool _endTimeKeyboardVisible = false;
  bool _endTimeDirectInputActive = false;
  CommuteDestination? _pendingDestination;
  _CommuteGateView _gateView = _CommuteGateView.power;
  CommutePreClockInDecision? _preClockInDecision;
  final Set<String> _checkedPreClockInItemIds = <String>{};
  bool _preClockInConfirmed = false;
  bool _preClockInConfirming = false;
  int _moreOpenCount = 0;
  bool _forcePreClockInGateForAttempt = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String get _screenId =>
      widget.spec.traceScreenId ?? '${widget.spec.diagnosticKey}_commute_inside';

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
      reverseDuration: const Duration(milliseconds: 460),
    );
    controller.initialize(context);
    LauncherDiagnostics.record(
      'commute_power_gate_init',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'preClockInGate': widget.preClockInGate?.runtimeType.toString() ?? 'none',
      },
    );
    LauncherDiagnostics.record(
      'commute_menu_config',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'modeLauncherAction': 'removed',
        'developerStatus': 'developer_only',
        'menuMotionMs': _menuMotionDuration.inMilliseconds,
        'presentation': 'neutral_application_field',
      },
    );
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_prepareGate());
    });
  }

  void _startGateReveal({required String source}) {
    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_power_gate_reveal_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'source': source,
        'durationMs': _revealController.duration?.inMilliseconds ?? 0,
        'reduceMotion': _reduceMotion,
      },
    );
    if (_reduceMotion) {
      _revealController.value = 1;
      return;
    }
    _revealController
      ..stop()
      ..forward(from: 0);
  }

  void _trace(
    String name, {
    Map<String, dynamic>? meta,
  }) {
    if (!widget.spec.enableDebugTrace) return;
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _prepareGate() async {
    if (!mounted) return;
    final userState = context.read<UserState>();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final localIsWorking = prefs.getBool('isWorking') ?? false;
    final sessionIsWorking = userState.isWorking;
    LauncherDiagnostics.record(
      'commute_working_check_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'localIsWorking': localIsWorking,
        'sessionIsWorking': sessionIsWorking,
      },
    );

    if (sessionIsWorking != localIsWorking) {
      LauncherDiagnostics.record(
        'commute_working_state_mismatch',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'localIsWorking': localIsWorking,
          'sessionIsWorking': sessionIsWorking,
        },
      );
      await userState.setWorkingStatus(localIsWorking);
      if (!mounted) return;
      LauncherDiagnostics.record(
        'commute_working_state_reconciled',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'localIsWorking': localIsWorking,
          'sessionIsWorking': userState.isWorking,
        },
      );
    }

    await userState.ensureTodayClockInStatus();
    if (!mounted) return;

    if (userState.isWorking && !userState.hasClockInToday) {
      LauncherDiagnostics.record(
        'commute_stale_working_detected',
        scope: 'commute_power',
        meta: <String, Object?>{'mode': widget.spec.diagnosticKey},
      );
      await _resetStaleWorkingState();
    }
    if (!mounted) return;

    if (userState.isWorking) {
      LauncherDiagnostics.record(
        'commute_redirect_working',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'hasClockInToday': userState.hasClockInToday,
          'gateRevealStarted': _revealController.value > 0,
        },
      );
      setState(() {
        _routeTransitioning = true;
      });
      final destination = await controller.redirectIfWorking(
        context,
        userState,
      );
      if (!mounted || destination != CommuteDestination.none) return;
      setState(() {
        _routeTransitioning = false;
        _stage = _CommutePowerGateStage.ready;
        _stateMessage = '';
      });
      _startGateReveal(source: 'working_redirect_unresolved');
      return;
    }

    setState(() {
      _stage = _CommutePowerGateStage.ready;
      _stateMessage = '';
    });
    LauncherDiagnostics.record(
      'commute_power_gate_ready',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.diagnosticKey},
    );
    _startGateReveal(source: 'not_working');
  }

  Future<void> _resetStaleWorkingState() async {
    await CommonAttendanceService.resetStaleWorkingState(
      context,
      source: 'commute_gate_stale:${widget.spec.diagnosticKey}',
      modeKey: widget.spec.modeKey,
      isHeadquarter: widget.spec.isHeadquarterContext ? true : null,
    );
  }

  Future<void> _handleLogout() async {
    if (_stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success) {
      return;
    }
    LauncherDiagnostics.record(
      'commute_logout_requested',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.diagnosticKey},
    );
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: false,
      delay: const Duration(milliseconds: 500),
      useCommonUi: true,
    );
  }

  Future<void> _handleAppExit() async {
    if (_stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success) {
      return;
    }
    LauncherDiagnostics.record(
      'commute_exit_requested',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.diagnosticKey},
    );
    await AppExitService.exitApp(context, useCommonUi: true);
  }

  Future<void> _resolveClockInIssue() async {
    if (_stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success ||
        _resolvingClockInIssue ||
        !_showClockInIssueResolution) {
      return;
    }

    setState(() {
      _resolvingClockInIssue = true;
      _clockInIssueState = CommuteClockInIssueState.resolving;
      _stateMessage = '출근 상태를 정리하고 있습니다.';
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
    });

    final userState = context.read<UserState>();
    LauncherDiagnostics.record(
      'commute_clock_in_issue_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'stage': _stage.name,
        'issueVisible': _showClockInIssueResolution,
      },
    );

    try {
      final clearResult = await userState.clearClockInIssueFlag();

      if (!clearResult.isSuccess) {
        await _handleClockInIssueFailure(
          reason: clearResult.failure?.name ?? 'unknown',
          detail: clearResult.detail ?? '',
          stackTrace: clearResult.stackTrace ?? '',
        );
        return;
      }
    } catch (error, stackTrace) {
      await _handleClockInIssueFailure(
        reason: 'unexpectedException',
        detail: error.toString(),
        stackTrace: stackTrace.toString(),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _resolvingClockInIssue = false;
      _showClockInIssueResolution = false;
      _clockInIssueState = CommuteClockInIssueState.success;
      _stateMessage = '출근 상태를 정리했습니다.';
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
    });

    LauncherDiagnostics.record(
      'commute_clock_in_issue_action_hidden',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'reason': 'resolved',
      },
    );
    LauncherDiagnostics.record(
      'commute_clock_in_issue_complete',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'working': userState.isWorking,
        'clockInToday': userState.hasClockInToday,
      },
    );

    await HapticFeedback.lightImpact();
  }

  Future<void> _handleClockInIssueFailure({
    required String reason,
    required String detail,
    required String stackTrace,
  }) async {
    LauncherDiagnostics.record(
      'commute_clock_in_issue_failure',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'reason': reason,
        if (detail.isNotEmpty) 'detail': detail,
        if (stackTrace.isNotEmpty) 'stack': stackTrace,
      },
    );

    if (!mounted) return;
    setState(() {
      _resolvingClockInIssue = false;
      _showClockInIssueResolution = true;
      _clockInIssueState = CommuteClockInIssueState.failure;
      _stateMessage = '출근 상태를 정리하지 못했습니다.';
      _clockInIssueFailureReason = reason;
      _clockInIssueFailureDetail = detail;
    });

    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted) return;

    LauncherDiagnostics.record(
      'commute_clock_in_issue_failure_developer_status',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'reason': reason,
        if (detail.isNotEmpty) 'detail': detail,
      },
    );
    await _showDeveloperStatus();
  }

  Future<void> _showDeveloperStatus() async {
    final userState = context.read<UserState>();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final localIsWorking = prefs.getBool('isWorking') ?? false;
    LauncherDiagnostics.record(
      'commute_status_requested',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.diagnosticKey},
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Commute Application Status',
      description: <String>[
        'Context: ${widget.spec.diagnosticKey}',
        'Stage: ${_stage.name}',
        'Working session: ${userState.isWorking}',
        'Working local: $localIsWorking',
        'Working synchronized: ${userState.isWorking == localIsWorking}',
        'Clock-in today: ${userState.hasClockInToday}',
        'Issue action visible: $_showClockInIssueResolution',
        'Issue resolving: $_resolvingClockInIssue',
        'Clock-in issue state: ${_clockInIssueState?.name ?? 'none'}',
        'Issue failure reason: $_clockInIssueFailureReason',
        'Issue failure detail: $_clockInIssueFailureDetail',
        'State message: $_stateMessage',
        'Mode launcher action: removed',
        'Developer status: developer_only',
        'Menu motion ms: ${_menuMotionDuration.inMilliseconds}',
        'Pre-clock-in gate: ${widget.preClockInGate == null ? 'disabled' : 'enabled'}',
        'Pre-clock-in gate type: ${widget.preClockInGate?.runtimeType.toString() ?? 'none'}',
        'Pre-clock-in view: ${_gateView.name}',
        'Pre-clock-in confirming: $_preClockInConfirming',
        'Pre-clock-in confirmed: $_preClockInConfirmed',
        'Pre-clock-in checked: ${_checkedPreClockInItemIds.length}/${_preClockInDecision?.items.length ?? 0}',
        'Pre-clock-in decision: ${_preClockInDecision?.reason ?? 'none'}',
        'Pre-clock-in context: ${_preClockInDecision?.contextLabel ?? ''}',
        'Pre-clock-in action surface: report_approval',
        'Pre-clock-in report layout: application_surface_embedded',
        'Pre-clock-in report menu: bottom_actions',
        'Pre-clock-in report motion ms: ${_preClockInChecklistMotionDuration.inMilliseconds}',
        'Pre-clock-in force armed: $_forcePreClockInGateForAttempt',
        'More open count: $_moreOpenCount',
        'Pre-clock-in diagnostics: ${_preClockInDecision?.diagnosticsSummary ?? ''}',
        'End-time console active: ${_endTimeRequirement != null}',
        'End-time day: ${_endTimeRequirement?.day ?? ''}',
        'End-time feedback: ${_endTimeFeedback.name}',
        'End-time draft: ${_endTimeDraft.hour.toString().padLeft(2, '0')}:${_endTimeDraft.minute.toString().padLeft(2, '0')}',
        'End-time input source: ${_endTimeInputSource.name}',
        'End-time input valid: $_endTimeInputValid',
        'End-time input text: $_endTimeInputText',
        'End-time direct hour: $_endTimeHourInput',
        'End-time direct minute: $_endTimeMinuteInput',
        'End-time focused field: ${_endTimeFocusedField.name}',
        'End-time keyboard visible: $_endTimeKeyboardVisible',
        'End-time direct input active: $_endTimeDirectInputActive',
        'Action attention: one_shot_console_impact',
        'Pending destination: ${_pendingDestination?.name ?? 'none'}',
        'Console flow: $_consoleFlow',
        'Attendance semantic status: ${_attendanceStatus.name}',
        'Workspace semantic status: ${_workspaceStatus.name}',
        'Application presentation: operational_status_console',
        'Application phase: ${_desktopKey.currentState?.diagnosticPhase ?? 'unmounted'}',
        'ParkinWorkin focused: ${_desktopKey.currentState?.applicationFocused ?? false}',
        'Start message visible: ${_desktopKey.currentState?.startMessageVisible ?? false}',
        'ParkinWorkin launched: ${_desktopKey.currentState?.applicationLaunched ?? false}',
        'Peripheral apps: ${_desktopKey.currentState?.peripheralCount ?? 0}',
        'Peripheral layout: ${_desktopKey.currentState?.peripheralLayout ?? 'unmounted'}',
        'Application field reveal ms: ${ParkinWorkinApplicationField.desktopRevealDuration.inMilliseconds}',
        'Pre-focus hold ms: ${ParkinWorkinApplicationField.preFocusHoldDuration.inMilliseconds}',
        'ParkinWorkin selection ms: ${ParkinWorkinApplicationField.selectionDuration.inMilliseconds}',
        'ParkinWorkin focus ms: ${ParkinWorkinApplicationField.focusDuration.inMilliseconds}',
        'Post-focus hold ms: ${ParkinWorkinApplicationField.postFocusHoldDuration.inMilliseconds}',
        'Start message ms: ${ParkinWorkinApplicationField.startMessageDuration.inMilliseconds}',
        'ParkinWorkin press ms: ${ParkinWorkinApplicationField.appPressDuration.inMilliseconds}',
        'ParkinWorkin launch ms: ${ParkinWorkinApplicationField.appLaunchDuration.inMilliseconds}',
        'Workspace expand ms: ${ParkinWorkinApplicationField.fullscreenDuration.inMilliseconds}',
        'Workspace render ms: ${CommuteDestinationCinematicEntry.renderDuration.inMilliseconds}',
      ].join('\n'),
      scope: 'commute_power',
    );
  }

  Future<void> _navigateWithCinematic({
    required String route,
    required String destination,
  }) async {
    if (_routeTransitioning || !mounted) return;
    setState(() => _routeTransitioning = true);
    LauncherDiagnostics.record(
      'commute_power_exit_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'destination': destination,
        'route': route,
      },
    );
    await _desktopKey.currentState?.expandToFullscreen();
    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_power_exit_complete',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'destination': destination,
        'route': route,
      },
    );
    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _startClockIn() async {
    if ((_stage != _CommutePowerGateStage.ready &&
            _stage != _CommutePowerGateStage.failure) ||
        _preClockInConfirming) {
      return;
    }

    final issueWasVisible = _showClockInIssueResolution;
    final hasPendingGate =
        widget.preClockInGate != null && !_preClockInConfirmed;
    setState(() {
      _stage = _CommutePowerGateStage.processing;
      _stateMessage = hasPendingGate
          ? '업무 확인 항목을 확인하고 있습니다.'
          : '출근 정보를 확인하고 있습니다.';
      _showClockInIssueResolution = false;
      _clockInIssueState = null;
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
      _endTimeRequirement = null;
      _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
      _pendingDestination = null;
    });
    if (issueWasVisible) {
      LauncherDiagnostics.record(
        'commute_clock_in_issue_action_hidden',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'reason': 'clock_in_retry',
        },
      );
    }
    LauncherDiagnostics.record(
      'commute_power_pressed',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'preClockInGate': widget.preClockInGate != null,
        'preClockInGateType':
            widget.preClockInGate?.runtimeType.toString() ?? 'none',
      },
    );
    _trace(
      'ParkinWorkin 실행',
      meta: <String, dynamic>{
        'screen': _screenId,
        'action': 'work_start_attempt',
        'isWorkingBefore': context.read<UserState>().isWorking,
      },
    );

    final gate = widget.preClockInGate;
    if (gate != null && !_preClockInConfirmed) {
      var decision = _preClockInDecision;
      if (decision == null) {
        final forceReminder = _forcePreClockInGateForAttempt;
        _forcePreClockInGateForAttempt = false;
        _moreOpenCount = 0;
        try {
          decision = await gate.evaluate(
            context,
            force: forceReminder,
          );
        } catch (error, stackTrace) {
          LauncherDiagnostics.record(
            'commute_pre_clock_in_gate_exception',
            scope: 'commute_todo',
            meta: <String, Object?>{
              'mode': widget.spec.diagnosticKey,
              'error': error,
              'stack': stackTrace,
              'decision': 'skip',
            },
          );
          decision = CommutePreClockInDecision.skip(
            reason: 'gate_exception',
            diagnosticsSummary: 'reason=gate_exception',
          );
        }
        _preClockInDecision = decision;
      }
      if (!mounted) return;

      LauncherDiagnostics.record(
        'commute_pre_clock_in_gate_decision',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'eligible': decision.eligible,
          'shouldShow': decision.shouldShow,
          'reason': decision.reason,
          'itemCount': decision.items.length,
        },
      );

      if (decision.shouldShow && decision.items.isNotEmpty) {
        setState(() {
          _stage = _CommutePowerGateStage.ready;
          _stateMessage = '';
          _gateView = _CommuteGateView.checklist;
          _checkedPreClockInItemIds.clear();
        });
        LauncherDiagnostics.record(
          'commute_pre_clock_in_report_presented',
          scope: 'commute_todo',
          meta: <String, Object?>{
            'mode': widget.spec.diagnosticKey,
            'context': decision.contextLabel,
            'itemCount': decision.items.length,
            'reason': decision.reason,
            'layout': 'application_window_embedded',
            'menuPlacement': 'bottom_actions',
            'firebaseRead': 0,
            'firebaseWrite': 0,
          },
        );
        await HapticFeedback.selectionClick();
        return;
      }
    }

    await _performClockIn();
  }

  void _togglePreClockInItem(String id) {
    if (_preClockInConfirming) return;
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    setState(() {
      if (_checkedPreClockInItemIds.contains(normalizedId)) {
        _checkedPreClockInItemIds.remove(normalizedId);
      } else {
        _checkedPreClockInItemIds.add(normalizedId);
      }
    });
    unawaited(HapticFeedback.selectionClick());
    LauncherDiagnostics.record(
      'commute_pre_clock_in_item_toggled',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'checkedCount': _checkedPreClockInItemIds.length,
        'itemCount': _preClockInDecision?.items.length ?? 0,
      },
    );
  }

  void _checkAllPreClockInItems() {
    if (_preClockInConfirming) return;
    final decision = _preClockInDecision;
    if (decision == null || decision.items.isEmpty) return;
    setState(() {
      _checkedPreClockInItemIds
        ..clear()
        ..addAll(decision.items.map((item) => item.id));
    });
    unawaited(HapticFeedback.selectionClick());
    LauncherDiagnostics.record(
      'commute_pre_clock_in_check_all',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'itemCount': decision.items.length,
        'interaction': 'report_checkbox',
      },
    );
  }

  Future<void> _confirmPreClockInChecklist() async {
    if (_preClockInConfirming) return;
    final decision = _preClockInDecision;
    final gate = widget.preClockInGate;
    if (decision == null || gate == null || decision.items.isEmpty) return;
    final allChecked = decision.items.every(
      (item) => _checkedPreClockInItemIds.contains(item.id),
    );
    if (!allChecked) return;

    unawaited(HapticFeedback.lightImpact());
    setState(() => _preClockInConfirming = true);
    LauncherDiagnostics.record(
      'commute_pre_clock_in_confirm_start',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'itemCount': decision.items.length,
        'reason': decision.reason,
        'interaction': 'report_confirmation',
      },
    );

    try {
      await gate.confirm(context, decision);
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'commute_pre_clock_in_confirm_exception',
        scope: 'commute_todo',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'error': error,
          'stack': stackTrace,
          'continueClockIn': true,
        },
      );
    }
    if (!mounted) return;

    setState(() {
      _preClockInConfirming = false;
      _preClockInConfirmed = true;
      _gateView = _CommuteGateView.power;
      _stage = _CommutePowerGateStage.processing;
      _stateMessage = '출근 정보를 확인하고 있습니다.';
    });
    LauncherDiagnostics.record(
      'commute_pre_clock_in_confirm_complete',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'itemCount': decision.items.length,
      },
    );
    await _performClockIn();
  }

  void _handleEndTimeDraftChanged(CommuteEndTimeDraftSnapshot snapshot) {
    final changed = snapshot.value.hour != _endTimeDraft.hour ||
        snapshot.value.minute != _endTimeDraft.minute ||
        snapshot.source != _endTimeInputSource ||
        snapshot.inputValid != _endTimeInputValid ||
        snapshot.inputText != _endTimeInputText ||
        snapshot.hourInput != _endTimeHourInput ||
        snapshot.minuteInput != _endTimeMinuteInput ||
        snapshot.focusedField != _endTimeFocusedField ||
        snapshot.keyboardVisible != _endTimeKeyboardVisible ||
        snapshot.directInputActive != _endTimeDirectInputActive;
    _endTimeDraft = snapshot.value;
    _endTimeInputSource = snapshot.source;
    _endTimeInputValid = snapshot.inputValid;
    _endTimeInputText = snapshot.inputText;
    _endTimeHourInput = snapshot.hourInput;
    _endTimeMinuteInput = snapshot.minuteInput;
    _endTimeFocusedField = snapshot.focusedField;
    _endTimeKeyboardVisible = snapshot.keyboardVisible;
    _endTimeDirectInputActive = snapshot.directInputActive;
    if (!changed) return;
    LauncherDiagnostics.record(
      'commute_end_time_draft_changed',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'time': '${snapshot.value.hour.toString().padLeft(2, '0')}:${snapshot.value.minute.toString().padLeft(2, '0')}',
        'source': snapshot.source.name,
        'inputValid': snapshot.inputValid,
        'inputText': snapshot.inputText,
        'hourInput': snapshot.hourInput,
        'minuteInput': snapshot.minuteInput,
        'focusedField': snapshot.focusedField.name,
        'keyboardVisible': snapshot.keyboardVisible,
        'directInputActive': snapshot.directInputActive,
      },
    );
  }

  Future<void> _prepareEndTimeOrContinue(
    CommuteDestination destination,
  ) async {
    final requirement = await resolveMissingWeekdayEndTimeRequirement(
      context,
      clockInAt: DateTime.now(),
    );
    if (!mounted) return;

    if (requirement == null) {
      await _continueAfterClockIn(destination);
      return;
    }

    setState(() {
      _endTimeRequirement = requirement;
      _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
      _endTimeDraft = const TimeOfDay(hour: 0, minute: 0);
      _endTimeInputSource = CommuteEndTimeInputSource.initial;
      _endTimeInputValid = true;
      _endTimeInputText = '00:00';
      _endTimeHourInput = '00';
      _endTimeMinuteInput = '00';
      _endTimeFocusedField = CommuteEndTimeInputField.none;
      _endTimeKeyboardVisible = false;
      _endTimeDirectInputActive = false;
      _pendingDestination = destination;
      _stateMessage = '퇴근 시간을 확인해 주세요.';
    });
    LauncherDiagnostics.record(
      'commute_end_time_inline_presented',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'day': requirement.day,
        'destination': destination.name,
        'presentation': 'operational_status_console',
      },
    );
  }

  Future<void> _skipEndTimeSetup() async {
    final destination = _pendingDestination;
    final requirement = _endTimeRequirement;
    if (destination == null || requirement == null) return;
    LauncherDiagnostics.record(
      'commute_end_time_inline_skipped',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'day': requirement.day,
        'destination': destination.name,
      },
    );
    await _continueAfterClockIn(destination);
  }

  Future<void> _saveEndTimeSetup(TimeOfDay value) async {
    final destination = _pendingDestination;
    final requirement = _endTimeRequirement;
    if (destination == null || requirement == null) return;
    if (_endTimeFeedback == CommuteEndTimeSetupFeedback.saving) return;

    setState(() {
      _endTimeFeedback = CommuteEndTimeSetupFeedback.saving;
      _stateMessage = '퇴근 시간을 저장하고 있습니다.';
    });
    LauncherDiagnostics.record(
      'commute_end_time_inline_save_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'day': requirement.day,
        'time': '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
      },
    );

    final saved = await saveMissingWeekdayEndTime(
      context,
      day: requirement.day,
      endTime: value,
    );
    if (!mounted) return;

    setState(() {
      _endTimeFeedback = saved
          ? CommuteEndTimeSetupFeedback.success
          : CommuteEndTimeSetupFeedback.failure;
      _stateMessage = saved
          ? '퇴근 시간을 저장했습니다.'
          : '퇴근 시간을 저장하지 못했습니다.';
    });
    LauncherDiagnostics.record(
      'commute_end_time_inline_save_complete',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'day': requirement.day,
        'saved': saved,
        'destination': destination.name,
      },
    );

    await Future<void>.delayed(
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 650),
    );
    if (!mounted) return;
    await _continueAfterClockIn(destination);
  }

  Future<void> _continueAfterClockIn(
    CommuteDestination destination,
  ) async {
    switch (destination) {
      case CommuteDestination.headquarter:
        LauncherDiagnostics.record(
          'commute_power_navigate',
          scope: 'commute_power',
          meta: <String, Object?>{
            'mode': widget.spec.diagnosticKey,
            'destination': 'headquarter',
            'route': widget.spec.headquarterRoute,
          },
        );
        _trace(
          '출근 라우팅',
          meta: <String, dynamic>{
            'screen': _screenId,
            'action': 'navigate',
            'to': widget.spec.headquarterRoute,
            'dest': 'headquarter',
          },
        );
        await _navigateWithCinematic(
          route: widget.spec.headquarterRoute,
          destination: 'headquarter',
        );
        break;
      case CommuteDestination.type:
        LauncherDiagnostics.record(
          'commute_power_navigate',
          scope: 'commute_power',
          meta: <String, Object?>{
            'mode': widget.spec.diagnosticKey,
            'destination': 'type',
            'route': widget.spec.typeRoute,
          },
        );
        _trace(
          '출근 라우팅',
          meta: <String, dynamic>{
            'screen': _screenId,
            'action': 'navigate',
            'to': widget.spec.typeRoute,
            'dest': 'type',
          },
        );
        await _navigateWithCinematic(
          route: widget.spec.typeRoute,
          destination: 'type',
        );
        break;
      case CommuteDestination.none:
        if (!mounted) return;
        setState(() {
          _stage = _CommutePowerGateStage.ready;
          _stateMessage = '';
          _showClockInIssueResolution = false;
          _clockInIssueState = null;
          _clockInIssueFailureReason = '';
          _clockInIssueFailureDetail = '';
          _endTimeRequirement = null;
          _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
          _pendingDestination = null;
        });
        break;
    }
  }

  Future<void> _performClockIn() async {
    if (!mounted) return;
    setState(() {
      _stage = _CommutePowerGateStage.processing;
      _stateMessage = '출근 정보를 확인하고 있습니다.';
      _showClockInIssueResolution = false;
      _clockInIssueState = null;
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
      _endTimeRequirement = null;
      _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
      _pendingDestination = null;
    });

    try {
      final result = await controller.handleWorkStatusAndDecide(
        context,
        context.read<UserState>(),
      );
      if (!mounted) return;

      LauncherDiagnostics.record(
        'commute_power_result',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'resultType': result.type.name,
          'destination': result.destination.name,
        },
      );
      _trace(
        '출근 처리 결과',
        meta: <String, dynamic>{
          'screen': _screenId,
          'action': 'work_start_result',
          'resultType': result.type.toString(),
          'dest': result.destination.toString(),
        },
      );

      if (result.type == CommuteResultType.failure) {
        setState(() {
          _stage = _CommutePowerGateStage.failure;
          _stateMessage = '출근을 시작하지 못했습니다.';
          _showClockInIssueResolution = false;
          _clockInIssueFailureReason = '';
          _clockInIssueFailureDetail = '';
        });
        await HapticFeedback.heavyImpact();
        if (!mounted) return;
        await StatusDialog.showFailure(
          context,
          title: '출근 실패',
          useCommonUi: true,
        );
        return;
      }

      if (result.type == CommuteResultType.alreadyWorked) {
        setState(() {
          _stage = _CommutePowerGateStage.ready;
          _stateMessage = '오늘 출근 기록이 이미 있습니다.';
          _showClockInIssueResolution = true;
          _clockInIssueState = CommuteClockInIssueState.available;
          _clockInIssueFailureReason = '';
          _clockInIssueFailureDetail = '';
        });
        LauncherDiagnostics.record(
          'commute_clock_in_issue_action_revealed',
          scope: 'commute_power',
          meta: <String, Object?>{
            'mode': widget.spec.diagnosticKey,
            'reason': 'already_worked',
          },
        );
        final developerMode = await DevAuth.isDevModeEnabled();
        if (developerMode && mounted) {
          LauncherDiagnostics.record(
            'commute_clock_in_issue_developer_status',
            scope: 'commute_power',
            meta: <String, Object?>{
              'mode': widget.spec.diagnosticKey,
              'reason': 'already_worked',
            },
          );
          await _showDeveloperStatus();
        }
        return;
      }

      final gate = widget.preClockInGate;
      final decision = _preClockInDecision;
      if (gate != null && decision != null) {
        try {
          await gate.onClockInSucceeded(context, decision);
        } catch (error, stackTrace) {
          LauncherDiagnostics.record(
            'commute_pre_clock_in_success_history_exception',
            scope: 'commute_todo',
            meta: <String, Object?>{
              'mode': widget.spec.diagnosticKey,
              'error': error,
              'stack': stackTrace,
            },
          );
        }
        if (!mounted) return;
      }

      setState(() {
        _stage = _CommutePowerGateStage.success;
        _stateMessage = '업무를 시작합니다.';
        _showClockInIssueResolution = false;
        _clockInIssueState = null;
        _clockInIssueFailureReason = '';
        _clockInIssueFailureDetail = '';
      });
      await HapticFeedback.lightImpact();
      await Future<void>.delayed(
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      );
      if (!mounted) return;

      await _prepareEndTimeOrContinue(result.destination);

    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'commute_power_exception',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.diagnosticKey,
          'error': error,
          'stack': stackTrace,
        },
      );
      if (!mounted) return;
      setState(() {
        _stage = _CommutePowerGateStage.failure;
        _stateMessage = '출근을 시작하지 못했습니다.';
        _showClockInIssueResolution = false;
        _clockInIssueState = null;
        _clockInIssueFailureReason = '';
        _clockInIssueFailureDetail = '';
        _endTimeRequirement = null;
        _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
        _pendingDestination = null;
      });
      await StatusDialog.showFailure(
        context,
        title: '출근 실패',
        useCommonUi: true,
      );
    }
  }

  SystemUiOverlayStyle _systemUiStyle(CommonUiTokens tokens) {
    final brightness = tokens.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: tokens.canvas,
      statusBarIconBrightness: brightness,
      statusBarBrightness: tokens.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: tokens.canvas,
      systemNavigationBarIconBrightness: brightness,
      systemNavigationBarDividerColor: tokens.canvas,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  void _handleMoreOpened() {
    if (widget.preClockInGate == null ||
        _preClockInConfirmed ||
        _preClockInConfirming ||
        _forcePreClockInGateForAttempt ||
        _gateView != _CommuteGateView.power ||
        _routeTransitioning ||
        (_stage != _CommutePowerGateStage.ready &&
            _stage != _CommutePowerGateStage.failure)) {
      return;
    }

    _moreOpenCount += 1;
    LauncherDiagnostics.record(
      'commute_more_opened',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'pressCount': _moreOpenCount,
        'forceEligible': true,
      },
    );

    if (_moreOpenCount < 2) return;

    _moreOpenCount = 0;
    _forcePreClockInGateForAttempt = true;
    _preClockInDecision = null;
    _checkedPreClockInItemIds.clear();
    unawaited(HapticFeedback.selectionClick());
    LauncherDiagnostics.record(
      'commute_pre_clock_in_force_armed',
      scope: 'commute_todo',
      meta: <String, Object?>{
        'mode': widget.spec.diagnosticKey,
        'source': 'more_opened_twice',
        'forceReminder': true,
      },
    );
  }

  PopupMenuItem<String> _menuItem({
    required CommonUiTokens tokens,
    required String value,
    required IconData icon,
    required String label,
    bool destructive = false,
  }) {
    final foreground = destructive ? tokens.danger : tokens.textPrimary;
    return PopupMenuItem<String>(
      value: value,
      height: 52,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: destructive ? tokens.danger : tokens.iconSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu(
    CommonUiTokens tokens,
    bool developerMode, {
    bool reportPlacement = false,
  }) {
    final disabled = _routeTransitioning ||
        _stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success ||
        _resolvingClockInIssue ||
        _endTimeFeedback == CommuteEndTimeSetupFeedback.saving ||
        _preClockInConfirming;
    final duration = _reduceMotion ? Duration.zero : _menuMotionDuration;
    final menuKey = ValueKey<String>(
      'commute_menu_${developerMode ? 'developer' : 'standard'}_${disabled ? 'disabled' : 'enabled'}',
    );

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      child: PopupMenuButton<String>(
        key: menuKey,
        enabled: !disabled,
        color: tokens.surfaceRaised,
        elevation: 0,
        offset: reportPlacement
            ? const Offset(0, 8)
            : const Offset(0, -8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          side: BorderSide(color: tokens.borderSubtle),
        ),
        onOpened: _handleMoreOpened,
        onSelected: (value) {
          switch (value) {
            case 'status':
              unawaited(_showDeveloperStatus());
              break;
            case 'logout':
              unawaited(_handleLogout());
              break;
            case 'exit_app':
              unawaited(_handleAppExit());
              break;
          }
        },
        itemBuilder: (context) => [
          if (developerMode) ...[
            _menuItem(
              tokens: tokens,
              value: 'status',
              icon: Icons.monitor_heart_outlined,
              label: 'STATUS',
            ),
            const PopupMenuDivider(height: 1),
          ],
          _menuItem(
            tokens: tokens,
            value: 'logout',
            icon: Icons.logout_rounded,
            label: '로그아웃',
            destructive: true,
          ),
          _menuItem(
            tokens: tokens,
            value: 'exit_app',
            icon: Icons.power_settings_new_rounded,
            label: '앱 종료',
            destructive: true,
          ),
        ],
        child: Semantics(
          button: true,
          enabled: !disabled,
          label: '더 보기',
          child: AnimatedScale(
            scale: disabled ? 0.96 : 1,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: disabled ? 0.35 : 1,
              duration: duration,
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.more_horiz_rounded,
                  color: tokens.iconSecondary,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ParkinWorkinDesktopStage get _desktopStage {
    return switch (_stage) {
      _CommutePowerGateStage.checking => ParkinWorkinDesktopStage.checking,
      _CommutePowerGateStage.ready => ParkinWorkinDesktopStage.ready,
      _CommutePowerGateStage.processing =>
        ParkinWorkinDesktopStage.processing,
      _CommutePowerGateStage.success => ParkinWorkinDesktopStage.success,
      _CommutePowerGateStage.failure => ParkinWorkinDesktopStage.failure,
    };
  }

  ParkinWorkinStepStatus get _attendanceStatus {
    final issueState = _clockInIssueState;
    if (issueState != null) {
      return switch (issueState) {
        CommuteClockInIssueState.available => ParkinWorkinStepStatus.issue,
        CommuteClockInIssueState.resolving =>
          ParkinWorkinStepStatus.checking,
        CommuteClockInIssueState.success => ParkinWorkinStepStatus.reset,
        CommuteClockInIssueState.failure => ParkinWorkinStepStatus.failure,
      };
    }
    return switch (_stage) {
      _CommutePowerGateStage.checking => ParkinWorkinStepStatus.checking,
      _CommutePowerGateStage.ready => ParkinWorkinStepStatus.waiting,
      _CommutePowerGateStage.processing => ParkinWorkinStepStatus.checking,
      _CommutePowerGateStage.success => ParkinWorkinStepStatus.ready,
      _CommutePowerGateStage.failure => ParkinWorkinStepStatus.failure,
    };
  }

  ParkinWorkinStepStatus get _workspaceStatus {
    if (_endTimeRequirement != null) {
      return switch (_endTimeFeedback) {
        CommuteEndTimeSetupFeedback.editing => ParkinWorkinStepStatus.pending,
        CommuteEndTimeSetupFeedback.saving => ParkinWorkinStepStatus.checking,
        CommuteEndTimeSetupFeedback.success => ParkinWorkinStepStatus.ready,
        CommuteEndTimeSetupFeedback.failure => ParkinWorkinStepStatus.pending,
      };
    }
    return _stage == _CommutePowerGateStage.success
        ? ParkinWorkinStepStatus.ready
        : ParkinWorkinStepStatus.waiting;
  }

  String get _consoleFlow {
    if (_gateView == _CommuteGateView.checklist &&
        _preClockInDecision != null) {
      return 'pre_clock_in_checklist';
    }
    if (_clockInIssueState != null) {
      return 'clock_in_issue_${_clockInIssueState!.name}';
    }
    if (_endTimeRequirement != null) {
      return 'end_time_${_endTimeFeedback.name}';
    }
    return 'status';
  }

  Widget _buildDesktopGate(UserState userState) {
    final name = userState.name.trim().isEmpty ? '사용자' : userState.name.trim();
    final reveal = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    final enabled = !_routeTransitioning &&
        (_stage == _CommutePowerGateStage.ready ||
            _stage == _CommutePowerGateStage.failure);
    final decision = _preClockInDecision;
    Widget? embeddedPanel;
    Widget? consoleExtension;

    if (_gateView == _CommuteGateView.checklist && decision != null) {
      embeddedPanel = TweenAnimationBuilder<double>(
        key: const ValueKey<String>('pre_clock_in_checklist_motion'),
        tween: Tween<double>(begin: 0, end: 1),
        duration: _reduceMotion
            ? Duration.zero
            : _preClockInChecklistMotionDuration,
        curve: Curves.easeOutCubic,
        child: CommutePreClockInChecklist(
          key: const ValueKey<String>('pre_clock_in_checklist'),
          contextLabel: decision.contextLabel,
          items: decision.items,
          checkedIds: _checkedPreClockInItemIds,
          onToggle: _togglePreClockInItem,
          onCheckAll: _checkAllPreClockInItems,
          onConfirm: _confirmPreClockInChecklist,
          confirming: _preClockInConfirming,
          embedded: true,
        ),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 18),
              child: child,
            ),
          );
        },
      );
    } else if (_clockInIssueState != null) {
      consoleExtension = CommuteClockInIssueConsoleSection(
        key: ValueKey<String>(
          'clock_in_issue_${_clockInIssueState!.name}',
        ),
        state: _clockInIssueState!,
        reduceMotion: _reduceMotion,
        onRetry: _resolveClockInIssue,
        onClockInAgain: _startClockIn,
      );
    } else if (_endTimeRequirement != null) {
      consoleExtension = CommuteEndTimeConsoleSection(
        key: ValueKey<String>('end_time_${_endTimeRequirement!.day}'),
        day: _endTimeRequirement!.day,
        reduceMotion: _reduceMotion,
        feedback: _endTimeFeedback,
        onSkip: _skipEndTimeSetup,
        onSave: _saveEndTimeSetup,
        onDraftChanged: _handleEndTimeDraftChanged,
      );
    }

    return AppStartCinematicReveal(
      animation: reveal,
      reduceMotion: _reduceMotion,
      exiting: _routeTransitioning,
      child: ParkinWorkinApplicationField(
        key: _desktopKey,
        userName: name,
        stage: _desktopStage,
        stateMessage: _stateMessage,
        enabled: enabled,
        reduceMotion: _reduceMotion,
        exiting: _routeTransitioning,
        modeKey: widget.spec.diagnosticKey,
        attendanceStatus: _attendanceStatus,
        workspaceStatus: _workspaceStatus,
        embeddedPanel: embeddedPanel,
        consoleExtension: consoleExtension,
        onLaunch: _startClockIn,
      ),
    );
  }

  Widget _buildBottomActions(
    CommonUiTokens tokens,
    bool developerMode,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
      child: Row(
        children: [
          const Spacer(),
          _buildMenu(tokens, developerMode),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: _systemUiStyle(tokens),
            child: PopScope(
              canPop: false,
              child: Scaffold(
                resizeToAvoidBottomInset: true,
                backgroundColor: tokens.canvas,
                body: SafeArea(
                  child: Consumer<UserState>(
                    builder: (context, userState, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: DevAuth.devModeEnabled,
                        builder: (context, developerMode, child) {
                          final transitionDuration = _reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.component;
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedSwitcher(
                                duration: transitionDuration,
                                reverseDuration: transitionDuration,
                                switchInCurve: CommonUiMotion.enter,
                                switchOutCurve: CommonUiMotion.exit,
                                transitionBuilder: (child, animation) {
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: CommonUiMotion.enter,
                                    reverseCurve: CommonUiMotion.exit,
                                  );
                                  final scale = Tween<double>(
                                    begin: 0.985,
                                    end: 1,
                                  ).animate(curved);
                                  return FadeTransition(
                                    opacity: curved,
                                    child: ScaleTransition(
                                      scale: scale,
                                      child: child,
                                    ),
                                  );
                                },
                                child: _stage ==
                                        _CommutePowerGateStage.checking
                                    ? const SizedBox.expand(
                                        key: ValueKey<String>(
                                          'commute_gate_checking_surface',
                                        ),
                                      )
                                    : KeyedSubtree(
                                        key: const ValueKey<String>(
                                          'application_field_gate',
                                        ),
                                        child: _buildDesktopGate(userState),
                                      ),
                              ),
                              if (_stage != _CommutePowerGateStage.checking)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: IgnorePointer(
                                    ignoring: _routeTransitioning,
                                    child: AnimatedOpacity(
                                      opacity: _routeTransitioning ? 0 : 1,
                                      duration: transitionDuration,
                                      curve: CommonUiMotion.exit,
                                      child: _buildBottomActions(
                                        tokens,
                                        developerMode,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
