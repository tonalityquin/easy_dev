import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/init/missing_weekday_end_time_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../../dashboard/applications/common/endtime_reminder_service.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../../launcher/application/launcher_diagnostics.dart';
import '../../../launcher/widgets/app_power_action_control.dart';
import '../../../selector/application/dev_auth.dart';
import '../../controllers/common_commute_in_controller.dart';
import '../../utils/commute_mode_spec.dart';

enum _CommutePowerGateStage {
  checking,
  ready,
  processing,
  success,
  failure,
}

class CommonCommuteInScreen extends StatefulWidget {
  const CommonCommuteInScreen({
    super.key,
    required this.spec,
  });

  final CommuteModeSpec spec;

  @override
  State<CommonCommuteInScreen> createState() => _CommonCommuteInScreenState();
}

class _CommonCommuteInScreenState extends State<CommonCommuteInScreen>
    with SingleTickerProviderStateMixin {
  late final CommonCommuteInController controller =
      CommonCommuteInController(spec: widget.spec);
  late final AnimationController _revealController;
  _CommutePowerGateStage _stage = _CommutePowerGateStage.checking;
  String _stateMessage = '';
  bool _routeTransitioning = false;
  bool _showClockInIssueResolution = false;
  bool _resolvingClockInIssue = false;
  String _clockInIssueFailureReason = '';
  String _clockInIssueFailureDetail = '';

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String get _screenId =>
      widget.spec.traceScreenId ?? '${widget.spec.modeKey}_commute_inside';

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
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareGate());
    });
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
    LauncherDiagnostics.record(
      'commute_working_check_start',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );

    await userState.ensureTodayClockInStatus();
    if (!mounted) return;

    if (userState.isWorking && !userState.hasClockInToday) {
      LauncherDiagnostics.record(
        'commute_stale_working_detected',
        scope: 'commute_power',
        meta: <String, Object?>{'mode': widget.spec.modeKey},
      );
      await _resetStaleWorkingState(userState);
    }
    if (!mounted) return;

    if (userState.isWorking) {
      LauncherDiagnostics.record(
        'commute_redirect_working',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.modeKey,
          'hasClockInToday': userState.hasClockInToday,
        },
      );
      controller.redirectIfWorking(context, userState);
      return;
    }

    setState(() {
      _stage = _CommutePowerGateStage.ready;
      _stateMessage = '';
    });
    LauncherDiagnostics.record(
      'commute_power_gate_ready',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );
    if (_reduceMotion) {
      _revealController.value = 1;
    } else {
      await _revealController.forward(from: 0);
    }
  }

  Future<void> _resetStaleWorkingState(UserState userState) async {
    await userState.isHeWorking();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kIsWorkingPrefsKey, false);
    await EndTimeReminderService.instance.cancel();
  }

  Future<void> _handleLogout() async {
    if (_stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success) {
      return;
    }
    LauncherDiagnostics.record(
      'commute_logout_requested',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.modeKey},
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
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );
    await AppExitService.exitApp(context, useCommonUi: true);
  }

  Future<void> _goToModeLauncher() async {
    if (_stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKeyMode);
    LauncherDiagnostics.record(
      'commute_mode_launcher_requested',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'savedModeCleared': true,
      },
    );
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.modeLauncher,
      (route) => false,
    );
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
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
    });

    final userState = context.read<UserState>();
    LauncherDiagnostics.record(
      'commute_clock_in_issue_start',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
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
      _stateMessage = '';
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
    });

    LauncherDiagnostics.record(
      'commute_clock_in_issue_action_hidden',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'reason': 'resolved',
      },
    );
    LauncherDiagnostics.record(
      'commute_clock_in_issue_complete',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'working': userState.isWorking,
        'clockInToday': userState.hasClockInToday,
      },
    );

    await HapticFeedback.lightImpact();
    if (!mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '출근 이슈 해결 완료',
      useCommonUi: true,
    );
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
        'mode': widget.spec.modeKey,
        'reason': reason,
        if (detail.isNotEmpty) 'detail': detail,
        if (stackTrace.isNotEmpty) 'stack': stackTrace,
      },
    );

    if (!mounted) return;
    setState(() {
      _resolvingClockInIssue = false;
      _showClockInIssueResolution = true;
      _stateMessage = '오늘 출근 기록이 이미 있습니다.';
      _clockInIssueFailureReason = reason;
      _clockInIssueFailureDetail = detail;
    });

    await HapticFeedback.heavyImpact();
    if (!mounted) return;
    await StatusDialog.showFailure(
      context,
      title: '출근 이슈 해결 실패',
      useCommonUi: true,
    );
    if (!mounted) return;

    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted) return;

    LauncherDiagnostics.record(
      'commute_clock_in_issue_failure_developer_status',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'reason': reason,
        if (detail.isNotEmpty) 'detail': detail,
      },
    );
    await _showDeveloperStatus();
  }

  Future<void> _showDeveloperStatus() async {
    final userState = context.read<UserState>();
    LauncherDiagnostics.record(
      'commute_status_requested',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Commute Power Status',
      description: <String>[
        'Mode: ${widget.spec.modeKey}',
        'Stage: ${_stage.name}',
        'Working: ${userState.isWorking}',
        'Clock-in today: ${userState.hasClockInToday}',
        'Issue action visible: $_showClockInIssueResolution',
        'Issue resolving: $_resolvingClockInIssue',
        'Issue failure reason: $_clockInIssueFailureReason',
        'Issue failure detail: $_clockInIssueFailureDetail',
        'State message: $_stateMessage',
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
        'mode': widget.spec.modeKey,
        'destination': destination,
        'route': route,
      },
    );
    if (_reduceMotion) {
      _revealController.value = 0;
    } else {
      await _revealController.reverse(from: 1);
    }
    if (!mounted) return;
    LauncherDiagnostics.record(
      'commute_power_exit_complete',
      scope: 'commute_power',
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'destination': destination,
        'route': route,
      },
    );
    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _startClockIn() async {
    if (_stage != _CommutePowerGateStage.ready &&
        _stage != _CommutePowerGateStage.failure) {
      return;
    }

    final issueWasVisible = _showClockInIssueResolution;
    setState(() {
      _stage = _CommutePowerGateStage.processing;
      _stateMessage = '출근 정보를 확인하고 있습니다.';
      _showClockInIssueResolution = false;
      _clockInIssueFailureReason = '';
      _clockInIssueFailureDetail = '';
    });
    if (issueWasVisible) {
      LauncherDiagnostics.record(
        'commute_clock_in_issue_action_hidden',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.modeKey,
          'reason': 'clock_in_retry',
        },
      );
    }
    LauncherDiagnostics.record(
      'commute_power_pressed',
      scope: 'commute_power',
      meta: <String, Object?>{'mode': widget.spec.modeKey},
    );
    _trace(
      '출근 파워 버튼',
      meta: <String, dynamic>{
        'screen': _screenId,
        'action': 'work_start_attempt',
        'isWorkingBefore': context.read<UserState>().isWorking,
      },
    );

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
          'mode': widget.spec.modeKey,
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
          _clockInIssueFailureReason = '';
          _clockInIssueFailureDetail = '';
        });
        LauncherDiagnostics.record(
          'commute_clock_in_issue_action_revealed',
          scope: 'commute_power',
          meta: <String, Object?>{
            'mode': widget.spec.modeKey,
            'reason': 'already_worked',
          },
        );
        final developerMode = await DevAuth.isDevModeEnabled();
        if (developerMode && mounted) {
          LauncherDiagnostics.record(
            'commute_clock_in_issue_developer_status',
            scope: 'commute_power',
            meta: <String, Object?>{
              'mode': widget.spec.modeKey,
              'reason': 'already_worked',
            },
          );
          await _showDeveloperStatus();
        }
        return;
      }

      setState(() {
        _stage = _CommutePowerGateStage.success;
        _stateMessage = '업무를 시작합니다.';
        _showClockInIssueResolution = false;
        _clockInIssueFailureReason = '';
        _clockInIssueFailureDetail = '';
      });
      await HapticFeedback.lightImpact();
      await Future<void>.delayed(
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      );
      if (!mounted) return;

      await showMissingWeekdayEndTimeDialogIfNeeded(
        context,
        clockInAt: DateTime.now(),
        useCommonUi: true,
      );
      if (!mounted) return;

      switch (result.destination) {
        case CommuteDestination.headquarter:
          LauncherDiagnostics.record(
            'commute_power_navigate',
            scope: 'commute_power',
            meta: <String, Object?>{
              'mode': widget.spec.modeKey,
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
              'mode': widget.spec.modeKey,
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
          setState(() {
            _stage = _CommutePowerGateStage.ready;
            _stateMessage = '';
            _showClockInIssueResolution = false;
            _clockInIssueFailureReason = '';
            _clockInIssueFailureDetail = '';
          });
          break;
      }
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'commute_power_exception',
        scope: 'commute_power',
        meta: <String, Object?>{
          'mode': widget.spec.modeKey,
          'error': error,
          'stack': stackTrace,
        },
      );
      if (!mounted) return;
      setState(() {
        _stage = _CommutePowerGateStage.failure;
        _stateMessage = '출근을 시작하지 못했습니다.';
        _showClockInIssueResolution = false;
        _clockInIssueFailureReason = '';
        _clockInIssueFailureDetail = '';
      });
      await StatusDialog.showFailure(
        context,
        title: '출근 실패',
        useCommonUi: true,
      );
    }
  }

  AppPowerActionVisualState get _powerVisualState {
    switch (_stage) {
      case _CommutePowerGateStage.checking:
      case _CommutePowerGateStage.ready:
        return AppPowerActionVisualState.idle;
      case _CommutePowerGateStage.processing:
        return AppPowerActionVisualState.processing;
      case _CommutePowerGateStage.success:
        return AppPowerActionVisualState.success;
      case _CommutePowerGateStage.failure:
        return AppPowerActionVisualState.failure;
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

  Widget _buildMenu(CommonUiTokens tokens, bool developerMode) {
    final disabled = _routeTransitioning ||
        _stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success;
    return PopupMenuButton<String>(
      enabled: !disabled,
      tooltip: '메뉴',
      color: tokens.surfaceRaised,
      elevation: 0,
      offset: const Offset(0, -8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      onSelected: (value) {
        switch (value) {
          case 'mode_launcher':
            unawaited(_goToModeLauncher());
            break;
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
        _menuItem(
          tokens: tokens,
          value: 'mode_launcher',
          icon: Icons.terminal_rounded,
          label: '모드 선택으로 되돌아가기',
        ),
        if (developerMode) ...[
          const PopupMenuDivider(height: 1),
          _menuItem(
            tokens: tokens,
            value: 'status',
            icon: Icons.monitor_heart_outlined,
            label: 'STATUS',
          ),
        ],
        const PopupMenuDivider(height: 1),
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
        child: AnimatedOpacity(
          opacity: disabled ? 0.35 : 1,
          duration:
              _reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
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
    );
  }

  Widget _buildPowerGate(
    BuildContext context,
    CommonUiTokens tokens,
    UserState userState,
  ) {
    final name = userState.name.trim().isEmpty ? '사용자' : userState.name.trim();
    final reveal = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    final enabled = !_routeTransitioning &&
        (_stage == _CommutePowerGateStage.ready ||
            _stage == _CommutePowerGateStage.failure);

    return AppStartCinematicReveal(
      animation: reveal,
      reduceMotion: _reduceMotion,
      exiting: _routeTransitioning,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppPowerActionControl(
                semanticLabel: '$name님 업무 시작',
                enabled: enabled,
                state: _powerVisualState,
                onPressed: _startClockIn,
              ),
              const SizedBox(height: 30),
              AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey<String>('${_stage.name}:$_stateMessage'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$name님, 오늘의 업무를 시작할까요?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                            height: 1.45,
                          ),
                    ),
                    AnimatedSize(
                      duration: _reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _stateMessage.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _stateMessage,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: _stage ==
                                              _CommutePowerGateStage.failure
                                          ? tokens.danger
                                          : _stage ==
                                                  _CommutePowerGateStage.success
                                              ? tokens.success
                                              : tokens.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(
    CommonUiTokens tokens,
    bool developerMode,
  ) {
    final disabled = _stage == _CommutePowerGateStage.processing ||
        _stage == _CommutePowerGateStage.success ||
        _resolvingClockInIssue;
    final duration = _reduceMotion ? Duration.zero : CommonUiMotion.component;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: duration,
            reverseDuration: duration,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: CommonUiMotion.enter,
                reverseCurve: CommonUiMotion.exit,
              );
              final slide = Tween<Offset>(
                begin: const Offset(-0.08, 0.16),
                end: Offset.zero,
              ).animate(curved);
              final scale = Tween<double>(
                begin: 0.96,
                end: 1,
              ).animate(curved);

              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: slide,
                  child: ScaleTransition(
                    scale: scale,
                    child: child,
                  ),
                ),
              );
            },
            child: _showClockInIssueResolution
                ? Semantics(
                    key: const ValueKey<String>(
                      'clock_in_issue_resolution_visible',
                    ),
                    button: true,
                    enabled: !disabled,
                    label: '출근 이슈 해결',
                    child: AnimatedScale(
                      scale: _resolvingClockInIssue ? 0.97 : 1,
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.press,
                      curve: CommonUiMotion.standard,
                      child: AnimatedOpacity(
                        opacity: _resolvingClockInIssue ? 0.56 : 1,
                        duration: _reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        child: TextButton.icon(
                          onPressed: disabled ? null : _resolveClockInIssue,
                          icon: _resolvingClockInIssue
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: tokens.textSecondary,
                                  ),
                                )
                              : const Icon(
                                  Icons.build_circle_outlined,
                                  size: 18,
                                ),
                          label: const Text('출근 이슈 해결'),
                          style: TextButton.styleFrom(
                            foregroundColor: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>(
                      'clock_in_issue_resolution_hidden',
                    ),
                  ),
          ),
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
                backgroundColor: tokens.canvas,
                body: SafeArea(
                  child: Consumer<UserState>(
                    builder: (context, userState, _) {
                      return ValueListenableBuilder<bool>(
                        valueListenable: DevAuth.devModeEnabled,
                        builder: (context, developerMode, child) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedSwitcher(
                                duration: _reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 220),
                                child: _stage == _CommutePowerGateStage.checking
                                    ? const SizedBox.shrink(
                                        key: ValueKey<String>('checking'),
                                      )
                                    : Center(
                                        key: const ValueKey<String>('ready'),
                                        child: _buildPowerGate(
                                          context,
                                          tokens,
                                          userState,
                                        ),
                                      ),
                              ),
                              if (_stage != _CommutePowerGateStage.checking)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: _buildBottomActions(
                                    tokens,
                                    developerMode,
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
