import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/app_start_flow_prefs.dart';
import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/init/overlay_lifecycle_gate.dart';
import '../../../app/init/startup_tasks.dart';
import '../../../app/terminal/presentation/parkinworkin_terminal_screen.dart';
import '../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../selector/application/dev_auth.dart';
import '../application/launcher_actions.dart';
import '../application/launcher_diagnostics.dart';
import '../widgets/app_power_action_control.dart';

enum _PowerBootStage {
  ready,
  purposeIntro,
  purposeCategory,
  workPurposeIntro,
  workPurpose,
  purposeConfirmation,
  setupNotice,
  openingTerminal,
}

class PowerBootScreen extends StatefulWidget {
  const PowerBootScreen({
    super.key,
    this.startupReport,
  });

  final StartupReport? startupReport;

  @override
  State<PowerBootScreen> createState() => _PowerBootScreenState();
}

class _PowerBootScreenState extends State<PowerBootScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _cinematicEnterDuration = Duration(milliseconds: 620);
  static const Duration _cinematicExitDuration = Duration(milliseconds: 720);
  static const Duration _purposeIntroHoldDuration =
      Duration(milliseconds: 2800);
  static const Duration _workPurposeIntroHoldDuration =
      Duration(milliseconds: 2200);
  static const Duration _setupNoticeHoldDuration =
      Duration(milliseconds: 3600);
  static const Duration _choiceRevealDuration = Duration(milliseconds: 1080);

  late final AnimationController _revealController;
  _PowerBootStage _stage = _PowerBootStage.ready;
  AppStartUserPurpose? _selectedPurpose;
  AppStartUserPurpose? _pendingPurpose;
  bool _poweringOn = false;
  bool _purposeCommitting = false;
  bool _stageTransitioning = false;
  bool _cinematicExiting = false;
  bool _exiting = false;
  int _cinematicGeneration = 0;
  String _cinematicSequence = 'ready';

  bool get _interactionLocked =>
      _poweringOn || _purposeCommitting || _stageTransitioning || _exiting;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  StartupReport? get _report => widget.startupReport ?? StartupTasks.lastReport;

  @override
  void initState() {
    super.initState();
    OverlayLifecycleGate.lock(reason: 'power_boot');
    _revealController = AnimationController(
      vsync: this,
      duration: _cinematicEnterDuration,
      reverseDuration: _cinematicExitDuration,
    );
    AppStartDebugTrace.log('power_boot', 'screen_init');
    LauncherDiagnostics.record(
      'power_screen_init',
      scope: 'power_boot',
      meta: <String, Object?>{
        'startupReady': _report?.readyCount ?? 0,
      },
    );
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduceMotion) {
        _revealController.value = 1;
      } else {
        _revealController.forward(from: 0);
      }
    });
  }

  Future<void> _powerOn() async {
    if (_interactionLocked || _stage != _PowerBootStage.ready) return;
    setState(() => _poweringOn = true);
    AppStartDebugTrace.log('power_boot', 'power_pressed');
    LauncherDiagnostics.record(
      'power_pressed',
      scope: 'power_boot',
      meta: <String, Object?>{
        'startupReady': _report?.readyCount ?? 0,
      },
    );
    final purpose = await AppStartFlowPrefs.getUserPurpose();
    if (!mounted) return;
    if (purpose != null) {
      _selectedPurpose = purpose;
      AppStartDebugTrace.log(
        'power_boot',
        'purpose_already_committed',
        meta: <String, Object?>{'purpose': purpose.storageValue},
      );
      await _openTerminal();
      return;
    }
    setState(() => _poweringOn = false);
    await _runCinematicPromptSequence(
      promptStage: _PowerBootStage.purposeIntro,
      choicesStage: _PowerBootStage.purposeCategory,
      holdDuration: _purposeIntroHoldDuration,
      sequence: 'purpose_category',
      promptVisibleEvent: 'purpose_intro_visible',
      choicesVisibleEvent: 'purpose_category_entered',
    );
  }

  Future<void> _runCinematicPromptSequence({
    required _PowerBootStage promptStage,
    required _PowerBootStage choicesStage,
    required Duration holdDuration,
    required String sequence,
    required String promptVisibleEvent,
    required String choicesVisibleEvent,
  }) async {
    if (_stageTransitioning || !mounted) return;
    final generation = ++_cinematicGeneration;
    setState(() {
      _stageTransitioning = true;
      _cinematicExiting = false;
      _cinematicSequence = sequence;
    });
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_sequence_start',
      meta: <String, Object?>{
        'sequence': sequence,
        'from': _stage.name,
        'promptStage': promptStage.name,
        'choicesStage': choicesStage.name,
        'enterMs': _cinematicEnterDuration.inMilliseconds,
        'holdMs': holdDuration.inMilliseconds,
        'exitMs': _cinematicExitDuration.inMilliseconds,
      },
    );

    if (!_reduceMotion && _revealController.value > 0) {
      try {
        await _revealController.reverse(from: _revealController.value).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    setState(() {
      _stage = promptStage;
      _cinematicExiting = false;
    });
    _revealController.duration = _cinematicEnterDuration;
    _revealController.reverseDuration = _cinematicExitDuration;
    _revealController.value = 0;
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_prompt_enter_start',
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': promptStage.name,
      },
    );

    if (_reduceMotion) {
      _revealController.value = 1;
    } else {
      try {
        await _revealController.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    AppStartDebugTrace.log(
      'power_boot',
      promptVisibleEvent,
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': promptStage.name,
      },
    );

    await Future<void>.delayed(holdDuration);
    if (!mounted || generation != _cinematicGeneration) return;

    setState(() => _cinematicExiting = true);
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_prompt_exit_start',
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': promptStage.name,
      },
    );

    if (_reduceMotion) {
      _revealController.value = 0;
    } else {
      try {
        await _revealController.reverse(from: 1).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_prompt_exit_complete',
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': promptStage.name,
      },
    );

    setState(() {
      _stage = choicesStage;
      _cinematicExiting = false;
    });
    _revealController.duration = _choiceRevealDuration;
    _revealController.value = 0;
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_choices_reveal_start',
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': choicesStage.name,
      },
    );

    if (_reduceMotion) {
      _revealController.value = 1;
    } else {
      try {
        await _revealController.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    setState(() => _stageTransitioning = false);
    AppStartDebugTrace.log(
      'power_boot',
      choicesVisibleEvent,
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': choicesStage.name,
      },
    );
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_sequence_complete',
      meta: <String, Object?>{
        'sequence': sequence,
        'stage': choicesStage.name,
      },
    );
  }

  Future<void> _transitionToStage(
    _PowerBootStage stage, {
    required String event,
  }) async {
    if (_stageTransitioning || !mounted) return;
    setState(() => _stageTransitioning = true);
    AppStartDebugTrace.log(
      'power_boot',
      'cinematic_stage_transition_start',
      meta: <String, Object?>{
        'from': _stage.name,
        'to': stage.name,
        'event': event,
      },
    );
    if (!_reduceMotion && _revealController.value > 0) {
      try {
        await _revealController.reverse(from: _revealController.value).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _stageTransitioning = false;
    });
    _revealController.duration = stage == _PowerBootStage.ready
        ? _cinematicEnterDuration
        : _choiceRevealDuration;
    _revealController.reverseDuration = _cinematicExitDuration;
    if (_reduceMotion) {
      _revealController.value = 1;
    } else {
      try {
        await _revealController.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    AppStartDebugTrace.log(
      'power_boot',
      event,
      meta: <String, Object?>{'stage': stage.name},
    );
  }

  Future<void> _selectTopPurpose(String category) async {
    if (_interactionLocked || _stage != _PowerBootStage.purposeCategory) return;
    await HapticFeedback.selectionClick();
    AppStartDebugTrace.log(
      'power_boot',
      'purpose_category_selected',
      meta: <String, Object?>{'category': category},
    );
    switch (category) {
      case 'work':
        await _runCinematicPromptSequence(
          promptStage: _PowerBootStage.workPurposeIntro,
          choicesStage: _PowerBootStage.workPurpose,
          holdDuration: _workPurposeIntroHoldDuration,
          sequence: 'work_purpose',
          promptVisibleEvent: 'work_purpose_intro_visible',
          choicesVisibleEvent: 'work_purpose_entered',
        );
        return;
      case 'personal':
        await _preparePurposeConfirmation(AppStartUserPurpose.personal);
        return;
      case 'device':
        await _preparePurposeConfirmation(
          AppStartUserPurpose.tabletInstallation,
        );
        return;
    }
  }

  Future<void> _selectWorkPurpose(AppStartUserPurpose purpose) async {
    if (_interactionLocked || _stage != _PowerBootStage.workPurpose) return;
    if (purpose != AppStartUserPurpose.branchEmployee &&
        purpose != AppStartUserPurpose.headOfficeEmployee &&
        purpose != AppStartUserPurpose.commuteRecorder) {
      return;
    }
    await HapticFeedback.selectionClick();
    await _preparePurposeConfirmation(purpose);
  }

  Future<void> _preparePurposeConfirmation(
    AppStartUserPurpose purpose,
  ) async {
    if (_interactionLocked) return;
    setState(() => _pendingPurpose = purpose);
    AppStartDebugTrace.log(
      'power_boot',
      'purpose_pending_selected',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'label': purpose.label,
        'confirmationLabel': purpose.confirmationLabel,
      },
    );
    LauncherDiagnostics.record(
      'startup_purpose_pending_selected',
      scope: 'power_boot',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'confirmationLabel': purpose.confirmationLabel,
      },
    );
    await _transitionToStage(
      _PowerBootStage.purposeConfirmation,
      event: 'purpose_confirmation_entered',
    );
  }

  Future<void> _confirmPendingPurpose() async {
    if (_interactionLocked || _stage != _PowerBootStage.purposeConfirmation) {
      return;
    }
    final purpose = _pendingPurpose;
    if (purpose == null) {
      AppStartDebugTrace.log(
        'power_boot',
        'purpose_confirmation_missing_pending',
      );
      await _restartPurposeSelection();
      return;
    }
    setState(() => _purposeCommitting = true);
    await HapticFeedback.mediumImpact();
    AppStartDebugTrace.log(
      'power_boot',
      'purpose_confirmation_confirmed',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'confirmationLabel': purpose.confirmationLabel,
      },
    );
    LauncherDiagnostics.record(
      'startup_purpose_confirmation_confirmed',
      scope: 'power_boot',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );
    await _runSetupNoticeAndCommit(purpose);
  }

  Future<void> _restartPurposeSelection() async {
    if (_interactionLocked || _stage != _PowerBootStage.purposeConfirmation) {
      return;
    }
    final discardedPurpose = _pendingPurpose;
    setState(() => _pendingPurpose = null);
    await HapticFeedback.selectionClick();
    AppStartDebugTrace.log(
      'power_boot',
      'purpose_confirmation_restarted',
      meta: <String, Object?>{
        'discardedPurpose': discardedPurpose?.storageValue ?? 'none',
      },
    );
    LauncherDiagnostics.record(
      'startup_purpose_confirmation_restarted',
      scope: 'power_boot',
      meta: <String, Object?>{
        'discardedPurpose': discardedPurpose?.storageValue ?? 'none',
      },
    );
    await _transitionToStage(
      _PowerBootStage.purposeCategory,
      event: 'purpose_category_restarted',
    );
  }

  Future<void> _runSetupNoticeAndCommit(
    AppStartUserPurpose purpose,
  ) async {
    if (!mounted) return;
    final generation = ++_cinematicGeneration;
    setState(() {
      _stageTransitioning = true;
      _cinematicExiting = true;
      _cinematicSequence = 'setup_notice';
    });
    AppStartDebugTrace.log(
      'power_boot',
      'setup_notice_sequence_start',
      meta: <String, Object?>{
        'purpose': purpose.storageValue,
        'from': _stage.name,
        'enterMs': _cinematicEnterDuration.inMilliseconds,
        'holdMs': _setupNoticeHoldDuration.inMilliseconds,
        'exitMs': _cinematicExitDuration.inMilliseconds,
      },
    );

    if (!_reduceMotion && _revealController.value > 0) {
      try {
        await _revealController.reverse(from: _revealController.value).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    setState(() {
      _stage = _PowerBootStage.setupNotice;
      _cinematicExiting = false;
    });
    _revealController.duration = _cinematicEnterDuration;
    _revealController.reverseDuration = _cinematicExitDuration;
    _revealController.value = 0;

    AppStartDebugTrace.log(
      'power_boot',
      'setup_notice_enter_start',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );

    if (_reduceMotion) {
      _revealController.value = 1;
    } else {
      try {
        await _revealController.forward(from: 0).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    AppStartDebugTrace.log(
      'power_boot',
      'setup_notice_visible',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );

    await Future<void>.delayed(_setupNoticeHoldDuration);
    if (!mounted || generation != _cinematicGeneration) return;

    setState(() => _cinematicExiting = true);
    AppStartDebugTrace.log(
      'power_boot',
      'setup_notice_exit_start',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );

    if (_reduceMotion) {
      _revealController.value = 0;
    } else {
      try {
        await _revealController.reverse(from: 1).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || generation != _cinematicGeneration) return;

    AppStartDebugTrace.log(
      'power_boot',
      'setup_notice_complete',
      meta: <String, Object?>{'purpose': purpose.storageValue},
    );

    try {
      await AppStartFlowPrefs.setUserPurpose(purpose);
      await AppStartFlowPrefs.setPermissionNoticeDone(true);
      if (!mounted || generation != _cinematicGeneration) return;
      setState(() {
        _selectedPurpose = purpose;
        _pendingPurpose = null;
        _stageTransitioning = false;
        _cinematicExiting = false;
      });
      AppStartDebugTrace.log(
        'power_boot',
        'purpose_committed',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'permissionNoticeDone': true,
        },
      );
      LauncherDiagnostics.record(
        'startup_purpose_committed',
        scope: 'power_boot',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'permissionNoticeDone': true,
        },
      );
      await _openTerminal();
    } catch (error, stackTrace) {
      AppStartDebugTrace.log(
        'power_boot',
        'purpose_commit_failure',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      LauncherDiagnostics.record(
        'startup_purpose_commit_failure',
        scope: 'power_boot',
        meta: <String, Object?>{
          'purpose': purpose.storageValue,
          'error': error,
        },
      );
      if (!mounted || generation != _cinematicGeneration) return;
      setState(() {
        _stage = _PowerBootStage.purposeConfirmation;
        _purposeCommitting = false;
        _stageTransitioning = false;
        _cinematicExiting = false;
      });
      _revealController.duration = _choiceRevealDuration;
      _revealController.reverseDuration = _cinematicExitDuration;
      if (_reduceMotion) {
        _revealController.value = 1;
      } else {
        _revealController.value = 0;
        try {
          await _revealController.forward(from: 0).orCancel;
        } on TickerCanceled {
          return;
        }
      }
    }
  }

  Future<void> _openTerminal() async {
    if (!mounted) return;
    setState(() {
      _stage = _PowerBootStage.openingTerminal;
      _poweringOn = true;
      _purposeCommitting = false;
    });
    AppStartDebugTrace.log(
      'power_boot',
      'terminal_open_requested',
      meta: <String, Object?>{
        'purpose': _selectedPurpose?.storageValue ?? 'existing',
      },
    );
    if (!_reduceMotion && _revealController.value > 0) {
      try {
        await _revealController.reverse(from: _revealController.value).orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    final reduceMotion = _reduceMotion;
    final report = _report;
    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: AppRoutes.modeLauncher),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ParkinWorkinTerminalScreen.launcher(startupReport: report);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .992, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    Navigator.of(context).pushReplacement(route);
  }

  Future<void> _openAbout() async {
    if (_interactionLocked || _stage != _PowerBootStage.ready) return;
    await HapticFeedback.selectionClick();
    LauncherDiagnostics.record(
      'power_about_requested',
      scope: 'power_boot',
    );
    await LauncherActions.openAbout(context);
    if (!mounted) return;
    LauncherDiagnostics.record(
      'power_about_returned',
      scope: 'power_boot',
    );
  }

  Future<void> _exitApp() async {
    if (_interactionLocked || _stage != _PowerBootStage.ready) return;
    setState(() => _exiting = true);
    try {
      await HapticFeedback.mediumImpact();
      LauncherDiagnostics.record(
        'power_exit_lock_start',
        scope: 'power_boot',
        meta: <String, Object?>{
          'poweringOn': _poweringOn,
          'exiting': _exiting,
        },
      );
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted) return;
      LauncherDiagnostics.record(
        'power_exit_requested',
        scope: 'power_boot',
      );
      await LauncherActions.exitApp(context);
      if (!mounted) return;
      LauncherDiagnostics.record(
        'power_exit_action_returned',
        scope: 'power_boot',
      );
    } finally {
      if (mounted) {
        setState(() => _exiting = false);
        LauncherDiagnostics.record(
          'power_exit_lock_release',
          scope: 'power_boot',
          meta: <String, Object?>{
            'poweringOn': _poweringOn,
            'exiting': _exiting,
          },
        );
      }
    }
  }

  Future<void> _showDeveloperStatus() async {
    final persistedPurpose = await AppStartFlowPrefs.getUserPurpose();
    final permissionNoticeDone =
        await AppStartFlowPrefs.getPermissionNoticeDone();
    if (!mounted) return;
    LauncherDiagnostics.record(
      'power_status_requested',
      scope: 'power_boot',
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Power Boot Status',
      description: <String>[
        'Stage: ${_stage.name}',
        'Cinematic reveal: ${_revealController.value.toStringAsFixed(3)}',
        'Cinematic sequence: $_cinematicSequence',
        'Cinematic exiting: $_cinematicExiting',
        'Cinematic enter ms: ${_cinematicEnterDuration.inMilliseconds}',
        'Cinematic exit ms: ${_cinematicExitDuration.inMilliseconds}',
        'Purpose intro hold ms: ${_purposeIntroHoldDuration.inMilliseconds}',
        'Work intro hold ms: ${_workPurposeIntroHoldDuration.inMilliseconds}',
        'Setup notice hold ms: ${_setupNoticeHoldDuration.inMilliseconds}',
        'Selected purpose: ${_selectedPurpose?.storageValue ?? '-'}',
        'Pending purpose: ${_pendingPurpose?.storageValue ?? '-'}',
        'Pending confirmation: ${_pendingPurpose?.confirmationLabel ?? '-'}',
        'Persisted purpose: ${persistedPurpose?.storageValue ?? '-'}',
        'Permission notice done: $permissionNoticeDone',
        'Startup ready: ${_report?.readyCount ?? 0}/4',
        'Notifications: ${_report?.notificationsReady == true ? 'READY' : 'WARN'}',
        'Reminder: ${_report?.reminderReady == true ? 'READY' : 'WARN'}',
        'Productivity store: ${_report?.chillStoreReady == true ? 'READY' : 'WARN'}',
        'Foreground service: ${_report?.foregroundServiceReady == true ? 'ACTIVE' : 'WARN'}',
        'Powering on: $_poweringOn',
        'Purpose committing: $_purposeCommitting',
        'Stage transitioning: $_stageTransitioning',
        'Exiting: $_exiting',
        'Interaction locked: $_interactionLocked',
        'Overlay lifecycle: ${OverlayLifecycleGate.stateLabel}',
        'Overlay gate reason: ${OverlayLifecycleGate.reason}',
        'Overlay runtime ready: ${OverlayLifecycleGate.runtimeReady}',
        'Overlay gate generation: ${OverlayLifecycleGate.generation}',
      ].join('\n'),
      scope: 'power_boot',
    );
  }

  Animation<double> _stageAnimation(double begin, double end) {
    if (_reduceMotion) return const AlwaysStoppedAnimation<double>(1);
    return CurvedAnimation(
      parent: _revealController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInOutCubic,
    );
  }

  Widget _buildPowerControl(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reveal = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    return AppStartCinematicReveal(
      animation: reveal,
      reduceMotion: _reduceMotion,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppPowerActionControl(
                semanticLabel: 'ParkinWorkin 시작',
                enabled: !_interactionLocked,
                state: _poweringOn
                    ? AppPowerActionVisualState.processing
                    : AppPowerActionVisualState.idle,
                onPressed: _powerOn,
              ),
              const SizedBox(height: 30),
              AnimatedOpacity(
                opacity: _interactionLocked ? 0.35 : 1,
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                child: Text(
                  '시작합니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurposeIntro(BuildContext context) {
    return _buildCinematicPrompt(
      context,
      '앱 시작에 앞서\n사용 목적에 맞는 버튼을 눌러주세요.',
    );
  }

  Widget _buildPurposeCategory(BuildContext context) {
    return _buildCinematicChoices(
      context,
      choices: <_CinematicChoiceData>[
        _CinematicChoiceData(
          label: '업무',
          selected: false,
          onPressed: () => _selectTopPurpose('work'),
        ),
        _CinematicChoiceData(
          label: '개인',
          selected: _selectedPurpose == AppStartUserPurpose.personal,
          onPressed: () => _selectTopPurpose('personal'),
        ),
        _CinematicChoiceData(
          label: '기기',
          selected:
              _selectedPurpose == AppStartUserPurpose.tabletInstallation,
          onPressed: () => _selectTopPurpose('device'),
        ),
      ],
    );
  }

  Widget _buildWorkPurposeIntro(BuildContext context) {
    return _buildCinematicPrompt(
      context,
      '업무 사용 유형에 맞는 버튼을 눌러주세요.',
    );
  }

  Widget _buildWorkPurpose(BuildContext context) {
    return _buildCinematicChoices(
      context,
      choices: <_CinematicChoiceData>[
        _CinematicChoiceData(
          label: '지사',
          selected: _selectedPurpose == AppStartUserPurpose.branchEmployee,
          onPressed: () =>
              _selectWorkPurpose(AppStartUserPurpose.branchEmployee),
        ),
        _CinematicChoiceData(
          label: '본사',
          selected:
              _selectedPurpose == AppStartUserPurpose.headOfficeEmployee,
          onPressed: () =>
              _selectWorkPurpose(AppStartUserPurpose.headOfficeEmployee),
        ),
        _CinematicChoiceData(
          label: '출퇴근 기록',
          selected: _selectedPurpose == AppStartUserPurpose.commuteRecorder,
          onPressed: () =>
              _selectWorkPurpose(AppStartUserPurpose.commuteRecorder),
        ),
      ],
    );
  }

  Widget _buildPurposeConfirmation(BuildContext context) {
    final purpose = _pendingPurpose;
    if (purpose == null) return const SizedBox.shrink();
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppStartCinematicReveal(
              animation: _stageAnimation(0, .42),
              reduceMotion: _reduceMotion,
              child: Text(
                purpose.confirmationLabel,
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppStartCinematicReveal(
              animation: _stageAnimation(.16, .58),
              reduceMotion: _reduceMotion,
              child: Text(
                '선택하신 사용 목적이 맞습니까?',
                textAlign: TextAlign.center,
                style: textTheme.headlineSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.65,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 28),
            AppStartCinematicReveal(
              animation: _stageAnimation(.36, .78),
              reduceMotion: _reduceMotion,
              child: _CinematicChoiceAction(
                label: '확인',
                enabled: !_interactionLocked,
                selected: false,
                reduceMotion: _reduceMotion,
                onPressed: _confirmPendingPurpose,
              ),
            ),
            const SizedBox(height: 10),
            AppStartCinematicReveal(
              animation: _stageAnimation(.58, 1),
              reduceMotion: _reduceMotion,
              child: _CinematicChoiceAction(
                label: '뒤로가기',
                enabled: !_interactionLocked,
                selected: false,
                reduceMotion: _reduceMotion,
                onPressed: _restartPurposeSelection,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupNotice(BuildContext context) {
    return _buildCinematicPrompt(
      context,
      '다음은 사용자가 선택한 목적에 따라 필요한 사용 권한과 이용 약관,\n'
      '개인정보보호, 외부 서비스 사용 등에 대한 동의 및 권한 요청을\n'
      '진행합니다.',
    );
  }

  Widget _buildCinematicPrompt(BuildContext context, String prompt) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final animation = CurvedAnimation(
      parent: _revealController,
      curve: _cinematicExiting ? Curves.easeInOutCubic : Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    return AppStartCinematicReveal(
      animation: animation,
      reduceMotion: _reduceMotion,
      exiting: _cinematicExiting,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Text(
            prompt,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.65,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCinematicChoices(
    BuildContext context, {
    required List<_CinematicChoiceData> choices,
  }) {
    const intervals = <(double, double)>[
      (0, .46),
      (.27, .73),
      (.54, 1.0),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              AppStartCinematicReveal(
                animation: _stageAnimation(intervals[i].$1, intervals[i].$2),
                reduceMotion: _reduceMotion,
                child: _CinematicChoiceAction(
                  label: choices[i].label,
                  enabled: !_interactionLocked,
                  selected: choices[i].selected,
                  reduceMotion: _reduceMotion,
                  onPressed: choices[i].onPressed,
                ),
              ),
              if (i < choices.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCenter(BuildContext context) {
    return switch (_stage) {
      _PowerBootStage.ready => _buildPowerControl(context),
      _PowerBootStage.purposeIntro => _buildPurposeIntro(context),
      _PowerBootStage.purposeCategory => _buildPurposeCategory(context),
      _PowerBootStage.workPurposeIntro => _buildWorkPurposeIntro(context),
      _PowerBootStage.workPurpose => _buildWorkPurpose(context),
      _PowerBootStage.purposeConfirmation =>
        _buildPurposeConfirmation(context),
      _PowerBootStage.setupNotice => _buildSetupNotice(context),
      _PowerBootStage.openingTerminal => const SizedBox.shrink(),
    };
  }

  Widget _buildFooterActions(BuildContext context) {
    if (_stage != _PowerBootStage.ready) return const SizedBox.shrink();
    final animation = _reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: _revealController,
            curve: const Interval(.28, 1, curve: Curves.easeOutCubic),
          );
    final slide = Tween<Offset>(
      begin: const Offset(0, .18),
      end: Offset.zero,
    ).animate(animation);
    return IgnorePointer(
      ignoring: _interactionLocked,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: slide,
          child: AnimatedOpacity(
            opacity: _exiting ? 0.82 : _poweringOn ? 0.28 : 1,
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PowerBootFooterAction(
                      label: '파킨워킨에 대해 알아보기',
                      icon: Icons.info_outline_rounded,
                      enabled: !_interactionLocked,
                      reduceMotion: _reduceMotion,
                      onPressed: _openAbout,
                    ),
                    const SizedBox(height: 4),
                    _PowerBootFooterAction(
                      label: '앱 종료',
                      icon: Icons.power_settings_new_rounded,
                      enabled: !_interactionLocked,
                      reduceMotion: _reduceMotion,
                      processing: _exiting,
                      destructive: true,
                      onPressed: _exitApp,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSystemBack() {
    if (_interactionLocked) return;
    if (_stage == _PowerBootStage.purposeConfirmation) {
      unawaited(_restartPurposeSelection());
      return;
    }
    if (_stage == _PowerBootStage.workPurpose) {
      unawaited(
        _transitionToStage(
          _PowerBootStage.purposeCategory,
          event: 'purpose_category_reopened',
        ),
      );
      return;
    }
    if (_stage == _PowerBootStage.purposeCategory) {
      unawaited(
        _transitionToStage(
          _PowerBootStage.ready,
          event: 'power_ready_reopened',
        ),
      );
    }
  }

  @override
  void dispose() {
    _cinematicGeneration++;
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final brightness = tokens.isDark ? Brightness.light : Brightness.dark;
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (!didPop) _handleSystemBack();
            },
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.canvas,
                statusBarIconBrightness: brightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: brightness,
                systemNavigationBarDividerColor: tokens.canvas,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _buildCenter(context)),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildFooterActions(context),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: DevAuth.devModeEnabled,
                          builder: (context, enabled, child) {
                            if (!enabled) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: IconButton.filledTonal(
                                onPressed: _interactionLocked
                                    ? null
                                    : _showDeveloperStatus,
                                icon: const Icon(Icons.terminal_rounded),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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

class _CinematicChoiceData {
  const _CinematicChoiceData({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final Future<void> Function() onPressed;
}

class _CinematicChoiceAction extends StatefulWidget {
  const _CinematicChoiceAction({
    required this.label,
    required this.enabled,
    required this.selected,
    required this.reduceMotion,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool selected;
  final bool reduceMotion;
  final Future<void> Function() onPressed;

  @override
  State<_CinematicChoiceAction> createState() => _CinematicChoiceActionState();
}

class _CinematicChoiceActionState extends State<_CinematicChoiceAction> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final active = _pressed || _hovered || widget.selected;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedScale(
          scale: _pressed ? .975 : 1,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            width: 300,
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: active ? tokens.surfaceSelected : tokens.transparent,
              borderRadius: BorderRadius.circular(CommonUiShapes.button),
              border: Border.all(
                color: active ? tokens.accent : tokens.borderSubtle,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.enabled ? widget.onPressed : null,
                onHighlightChanged: (value) {
                  if (_pressed == value) return;
                  setState(() => _pressed = value);
                },
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: widget.enabled
                                    ? tokens.textPrimary
                                    : tokens.textDisabled,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.1,
                              ),
                        ),
                        AnimatedSize(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          child: widget.selected
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(
                                    Icons.check_rounded,
                                    size: 19,
                                    color: tokens.accent,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerBootFooterAction extends StatefulWidget {
  const _PowerBootFooterAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.reduceMotion,
    required this.onPressed,
    this.destructive = false,
    this.processing = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool reduceMotion;
  final Future<void> Function() onPressed;
  final bool destructive;
  final bool processing;

  @override
  State<_PowerBootFooterAction> createState() =>
      _PowerBootFooterActionState();
}

class _PowerBootFooterActionState extends State<_PowerBootFooterAction> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final baseColor = widget.destructive ? tokens.danger : tokens.textSecondary;
    final activeColor = widget.destructive ? tokens.danger : tokens.accent;
    final foreground = _pressed || _hovered ? activeColor : baseColor;
    final background = _pressed || _hovered
        ? (widget.destructive
            ? tokens.dangerContainer.withOpacity(tokens.isDark ? .42 : .56)
            : tokens.surfaceSelected)
        : tokens.transparent;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedScale(
          scale: _pressed ? .975 : 1,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(CommonUiShapes.button),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.enabled ? widget.onPressed : null,
                onHighlightChanged: (value) {
                  if (_pressed == value) return;
                  setState(() => _pressed = value);
                },
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: .82, end: 1)
                                    .animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: widget.processing
                              ? SizedBox(
                                  key: const ValueKey<String>('processing'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: activeColor,
                                  ),
                                )
                              : Icon(
                                  widget.icon,
                                  key: ValueKey<String>(
                                    'icon-${widget.icon.codePoint}',
                                  ),
                                  size: 18,
                                  color: widget.enabled
                                      ? foreground
                                      : tokens.textDisabled,
                                ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: widget.enabled
                                    ? foreground
                                    : tokens.textDisabled,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.1,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
