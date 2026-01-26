import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:easydev/routes.dart';
import 'package:easydev/states/user/user_state.dart';
import 'package:easydev/utils/block_dialogs/work_start_duration_blocking_dialog.dart';

// ✅ Trace 기록용 Recorder
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

import '../minor_commute_in_controller.dart';

class MinorCommuteInWorkButtonWidget extends StatelessWidget {
  final MinorCommuteInController controller;
  final ValueChanged<bool> onLoadingChanged;

  const MinorCommuteInWorkButtonWidget({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';

    final bg = isWorking ? cs.surfaceContainerLow : cs.primary;
    final fg = isWorking ? cs.onSurfaceVariant : cs.onPrimary;
    final border = isWorking ? cs.outlineVariant : cs.primary;

    return ElevatedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: BorderSide(color: border, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      onPressed: isWorking
          ? null
          : () async {
        _trace(
          context,
          '출근하기 버튼',
          meta: <String, dynamic>{
            'screen': 'minor_commute_inside',
            'action': 'work_start_attempt',
            'isWorkingBefore': isWorking,
          },
        );

        bool loadingTurnedOn = false;

        try {
          final proceed = await showWorkStartDurationBlockingDialog(
            context,
            message: '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.',
            duration: const Duration(seconds: 5),
          );

          _trace(
            context,
            '출근 다이얼로그 결과',
            meta: <String, dynamic>{
              'screen': 'minor_commute_inside',
              'action': 'work_start_dialog_result',
              'proceed': proceed,
              'durationSeconds': 5,
            },
          );

          if (!proceed) {
            _trace(
              context,
              '출근 처리 종료',
              meta: <String, dynamic>{
                'screen': 'minor_commute_inside',
                'action': 'work_start_aborted',
                'reason': 'user_cancelled_dialog',
              },
            );
            return;
          }

          if (!context.mounted) return;

          onLoadingChanged(true);
          loadingTurnedOn = true;

          final dest = await controller.handleWorkStatusAndDecide(
            context,
            context.read<UserState>(),
          );

          if (!context.mounted) return;

          _trace(
            context,
            '출근 처리 결과',
            meta: <String, dynamic>{
              'screen': 'minor_commute_inside',
              'action': 'work_start_result',
              'dest': dest.toString(),
            },
          );

          switch (dest) {
            case MinorCommuteDestination.headquarter:
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'minor_commute_inside',
                  'action': 'navigate',
                  'to': AppRoutes.minorHeadquarterPage,
                  'dest': 'headquarter',
                },
              );
              Navigator.pushReplacementNamed(context, AppRoutes.minorHeadquarterPage);
              break;

            case MinorCommuteDestination.type:
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'minor_commute_inside',
                  'action': 'navigate',
                  'to': AppRoutes.minorTypePage,
                  'dest': 'type',
                },
              );
              Navigator.pushReplacementNamed(context, AppRoutes.minorTypePage);
              break;

            case MinorCommuteDestination.none:
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'minor_commute_inside',
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
              'screen': 'minor_commute_inside',
              'action': 'exception',
              'error': e.toString(),
            },
          );
          rethrow;
        } finally {
          if (context.mounted && loadingTurnedOn) {
            onLoadingChanged(false);
          } else if (context.mounted) {
            onLoadingChanged(false);
          }
        }
      },
    );
  }
}
