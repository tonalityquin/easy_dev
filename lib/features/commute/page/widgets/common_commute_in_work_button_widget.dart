import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/missing_weekday_end_time_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/common_commute_in_controller.dart';
import '../../utils/commute_mode_spec.dart';

class CommonCommuteInWorkButtonWidget extends StatelessWidget {
  const CommonCommuteInWorkButtonWidget({
    super.key,
    required this.controller,
    required this.spec,
    required this.onLoadingChanged,
  });

  final CommonCommuteInController controller;
  final CommuteModeSpec spec;
  final ValueChanged<bool> onLoadingChanged;

  void _trace(
    BuildContext context,
    String name, {
    Map<String, dynamic>? meta,
  }) {
    if (!spec.enableDebugTrace) return;
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';
    final screenId = spec.traceScreenId ?? '${spec.modeKey}_commute_inside';

    return PromptButton(
      label: label,
      icon: isWorking ? Icons.task_alt_rounded : Icons.access_time_rounded,
      variant: isWorking
          ? PromptButtonVariant.secondary
          : PromptButtonVariant.primary,
      selected: isWorking,
      expand: true,
      minHeight: 58,
      haptic: PromptHaptic.medium,
      semanticsLabel: isWorking ? '현재 출근 중' : '출근하기',
      onPressed: isWorking
          ? null
          : () async {
              var loadingTurnedOn = false;

              _trace(
                context,
                '출근하기 버튼',
                meta: <String, dynamic>{
                  'screen': screenId,
                  'action': 'work_start_attempt',
                  'isWorkingBefore': isWorking,
                },
              );

              try {
                if (!context.mounted) return;

                onLoadingChanged(true);
                loadingTurnedOn = true;

                final result = await controller.handleWorkStatusAndDecide(
                  context,
                  context.read<UserState>(),
                );

                if (!context.mounted) return;

                _trace(
                  context,
                  '출근 처리 결과',
                  meta: <String, dynamic>{
                    'screen': screenId,
                    'action': 'work_start_result',
                    'resultType': result.type.toString(),
                    'dest': result.destination.toString(),
                  },
                );

                if (result.type == CommuteResultType.failure) {
                  await StatusDialog.showFailure(
                    context,
                    title: '출근 실패',
                    usePromptUi: true,
                  );
                  return;
                }

                if (result.type == CommuteResultType.success) {
                  if (loadingTurnedOn) {
                    onLoadingChanged(false);
                    loadingTurnedOn = false;
                  }
                  await showMissingWeekdayEndTimeDialogIfNeeded(
                    context,
                    clockInAt: DateTime.now(),
                    usePromptUi: true,
                  );
                  if (!context.mounted) return;
                }

                switch (result.destination) {
                  case CommuteDestination.headquarter:
                    _trace(
                      context,
                      '출근 라우팅',
                      meta: <String, dynamic>{
                        'screen': screenId,
                        'action': 'navigate',
                        'to': spec.headquarterRoute,
                        'dest': 'headquarter',
                      },
                    );
                    Navigator.pushReplacementNamed(
                      context,
                      spec.headquarterRoute,
                    );
                    break;
                  case CommuteDestination.type:
                    _trace(
                      context,
                      '출근 라우팅',
                      meta: <String, dynamic>{
                        'screen': screenId,
                        'action': 'navigate',
                        'to': spec.typeRoute,
                        'dest': 'type',
                      },
                    );
                    Navigator.pushReplacementNamed(
                      context,
                      spec.typeRoute,
                    );
                    break;
                  case CommuteDestination.none:
                    _trace(
                      context,
                      '출근 라우팅',
                      meta: <String, dynamic>{
                        'screen': screenId,
                        'action': 'no_navigation',
                        'dest': 'none',
                      },
                    );
                    break;
                }
              } catch (e) {
                _trace(
                  context,
                  '출근 처리 오류',
                  meta: <String, dynamic>{
                    'screen': screenId,
                    'action': 'exception',
                    'error': e.toString(),
                  },
                );
                rethrow;
              } finally {
                if (context.mounted && loadingTurnedOn) {
                  onLoadingChanged(false);
                }
              }
            },
    );
  }
}
