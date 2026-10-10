import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/motion_timing_diagnostics.dart';
import '../../../../app/init/missing_weekday_end_time_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/common_commute_in_controller.dart';
import '../../utils/commute_mode_spec.dart';
import 'commute_end_time_setup_panel.dart';

class CommonCommuteInWorkButtonWidget extends StatefulWidget {
  const CommonCommuteInWorkButtonWidget({
    super.key,
    required this.controller,
    required this.spec,
    required this.onLoadingChanged,
  });

  final CommonCommuteInController controller;
  final CommuteModeSpec spec;
  final ValueChanged<bool> onLoadingChanged;

  @override
  State<CommonCommuteInWorkButtonWidget> createState() =>
      _CommonCommuteInWorkButtonWidgetState();
}

class _CommonCommuteInWorkButtonWidgetState
    extends State<CommonCommuteInWorkButtonWidget> {
  MissingWeekdayEndTimeRequirement? _endTimeRequirement;
  CommuteEndTimeSetupFeedback _endTimeFeedback =
      CommuteEndTimeSetupFeedback.editing;
  CommuteDestination? _pendingDestination;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  String get _screenId =>
      widget.spec.traceScreenId ?? '${widget.spec.modeKey}_commute_inside';

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

  Future<void> _continueAfterClockIn(CommuteDestination destination) async {
    if (!mounted) return;
    switch (destination) {
      case CommuteDestination.headquarter:
        _trace(
          '출근 라우팅',
          meta: <String, dynamic>{
            'screen': _screenId,
            'action': 'navigate',
            'to': widget.spec.headquarterRoute,
            'dest': 'headquarter',
          },
        );
        Navigator.pushReplacementNamed(
          context,
          widget.spec.headquarterRoute,
        );
        break;
      case CommuteDestination.type:
        _trace(
          '출근 라우팅',
          meta: <String, dynamic>{
            'screen': _screenId,
            'action': 'navigate',
            'to': widget.spec.typeRoute,
            'dest': 'type',
          },
        );
        Navigator.pushReplacementNamed(
          context,
          widget.spec.typeRoute,
        );
        break;
      case CommuteDestination.none:
        _trace(
          '출근 라우팅',
          meta: <String, dynamic>{
            'screen': _screenId,
            'action': 'no_navigation',
            'dest': 'none',
          },
        );
        break;
    }
  }

  Future<void> _skipEndTimeSetup() async {
    final destination = _pendingDestination;
    final requirement = _endTimeRequirement;
    if (destination == null || requirement == null) return;
    _trace(
      '퇴근 시간 설정 넘기기',
      meta: <String, dynamic>{
        'screen': _screenId,
        'day': requirement.day,
        'dest': destination.name,
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
    });

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
    });

    _trace(
      '퇴근 시간 설정 결과',
      meta: <String, dynamic>{
        'screen': _screenId,
        'day': requirement.day,
        'saved': saved,
        'time': '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
        'dest': destination.name,
      },
    );

    await MotionTimingDiagnostics.waitForFlow(
      'commute_end_time_result',
      AppFlowPacing.commuteEndTimeResult,
      scope: 'commute_work_button',
      reduceMotion: _reduceMotion,
      meta: <String, Object?>{
        'mode': widget.spec.modeKey,
        'destination': destination.name,
      },
    );
    if (!mounted) return;
    await _continueAfterClockIn(destination);
  }

  Future<void> _handleClockIn() async {
    final userState = context.read<UserState>();
    var loadingTurnedOn = false;

    _trace(
      '출근하기 버튼',
      meta: <String, dynamic>{
        'screen': _screenId,
        'action': 'work_start_attempt',
        'isWorkingBefore': userState.isWorking,
      },
    );

    try {
      if (!mounted) return;
      widget.onLoadingChanged(true);
      loadingTurnedOn = true;

      final result = await widget.controller.handleWorkStatusAndDecide(
        context,
        context.read<UserState>(),
      );
      if (!mounted) return;

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
        await StatusDialog.showFailure(
          context,
          title: '출근 실패',
          useCommonUi: true,
        );
        return;
      }

      if (result.type == CommuteResultType.success) {
        if (loadingTurnedOn) {
          widget.onLoadingChanged(false);
          loadingTurnedOn = false;
        }
        final requirement = await resolveMissingWeekdayEndTimeRequirement(
          context,
          clockInAt: DateTime.now(),
        );
        if (!mounted) return;
        if (requirement != null) {
          setState(() {
            _endTimeRequirement = requirement;
            _endTimeFeedback = CommuteEndTimeSetupFeedback.editing;
            _pendingDestination = result.destination;
          });
          return;
        }
      }

      await _continueAfterClockIn(result.destination);
    } catch (error) {
      _trace(
        '출근 처리 오류',
        meta: <String, dynamic>{
          'screen': _screenId,
          'action': 'exception',
          'error': error.toString(),
        },
      );
      rethrow;
    } finally {
      if (mounted && loadingTurnedOn) {
        widget.onLoadingChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirement = _endTimeRequirement;
    if (requirement != null) {
      return CommuteEndTimeConsoleSection(
        day: requirement.day,
        reduceMotion: _reduceMotion,
        feedback: _endTimeFeedback,
        onSkip: _skipEndTimeSetup,
        onSave: _saveEndTimeSetup,
      );
    }

    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';
    final transitionDuration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 260);

    return AnimatedSwitcher(
      duration: transitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutBack,
              ),
            ),
            child: child,
          ),
        );
      },
      child: CommonButton(
        key: ValueKey<bool>(isWorking),
        label: label,
        icon: isWorking ? Icons.task_alt_rounded : Icons.access_time_rounded,
        variant: isWorking
            ? CommonButtonVariant.secondary
            : CommonButtonVariant.primary,
        selected: isWorking,
        expand: true,
        minHeight: 58,
        haptic: CommonHaptic.medium,
        semanticsLabel: isWorking ? '현재 출근 중' : '출근하기',
        onPressed: isWorking ? null : _handleClockIn,
      ),
    );
  }
}
